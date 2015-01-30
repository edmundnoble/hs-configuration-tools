{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UnicodeSyntax #-}

-- |
-- Module: Main
-- Copyright: Copyright © 2014 AlephCloud Systems, Inc.
-- License: MIT
-- Maintainer: Lars Kuhtz <lars@alephcloud.com>
-- Stability: experimental
--
module Main
( main
) where

import Configuration.Utils
import Configuration.Utils.Internal

import Control.Exception
import Control.Monad

import qualified Data.ByteString.Char8 as B8
import Data.IORef
import qualified Data.List as L
import Data.Monoid.Unicode
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Yaml as Yaml

import Distribution.Simple.Utils (withTempFile)

import Example hiding (main)

import Prelude.Unicode

import System.Environment
import System.IO

import PkgInfo_url_example_test

#ifdef REMOTE_CONFIGS
import Control.Concurrent
import qualified Data.ByteString.Lazy as LB
import qualified Data.Text.Encoding as T
import qualified Network.Wai as WAI
import qualified Network.Wai.Handler.Warp as WARP
import qualified Network.HTTP.Types as HTTP
#endif

-- -------------------------------------------------------------------------- --
-- Poor man's debugging

enableDebug ∷ Bool
enableDebug = True

debug
    ∷ Monad m
    ⇒ m ()
    → m ()
debug a
    | enableDebug = a
    | otherwise = return ()

-- -------------------------------------------------------------------------- --
-- main

#ifdef REMOTE_CONFIGS
serverPort ∷ Int
serverPort = 8283

serverUrl ∷ T.Text
serverUrl = "http://127.0.0.1:" ⊕ sshow serverPort
#endif

main ∷ IO ()
main =
    withTempFile "." "tmp_TestExample.yml" $ \tmpPath0 tmpHandle0 →
    withTempFile "." "tmp_TestExample.yml" $ \tmpPath1 tmpHandle1 → do

        B8.hPutStrLn tmpHandle0 ∘ Yaml.encode $ config0
        hClose tmpHandle0

        T.hPutStrLn tmpHandle1 config1Part
        hClose tmpHandle1

#ifdef REMOTE_CONFIGS
        void ∘ forkIO $ server serverPort
#endif
        (successes, failures) ← L.partition id <$> sequence
            × tests0
            ⊕ tests1 [T.pack tmpPath0, T.pack tmpPath1]
            ⊕ tests2 "test-2a-" (T.pack tmpPath0) (T.pack tmpPath1)
#ifdef REMOTE_CONFIGS
            ⊕ tests2 "test-2b-" (serverUrl ⊕ "/config0") (serverUrl ⊕ "/config1")
            ⊕ test3
#endif

        T.putStrLn $ "success: " ⊕ sshow (length successes)
        T.putStrLn $ "failures: " ⊕ sshow (length failures)
        unless (length failures ≡ 0) $ do
            debug $ do
                T.readFile tmpPath0 >>= T.putStrLn
                T.readFile tmpPath1 >>= T.putStrLn
            error "test suite failed"

-- -------------------------------------------------------------------------- --
-- Test Cases

#ifdef REMOTE_CONFIGS
-- | Test with invalid remote URLs
--
test3 ∷ [IO Bool]
test3 =
    [ runTest mainInfo "test-3-0" False [x0 d1]
    , runTest mainInfo "test-3-1" False [x1 d1]
    ]
  where
    x0 (ConfAssertion args l v) = ConfAssertion (("--config-file=http://invalid"):args) l v
    x1 (ConfAssertion args l v) = ConfAssertion (("--config-file=" ⊕ T.unpack serverUrl ⊕ "/invalid"):args) l v
#endif


-- | Tests with two configuration files
--
tests2
    ∷ T.Text
        -- ^ test label prefix
    → T.Text
        -- ^ file for config0
    → T.Text
        -- ^ file for config1
    → [IO Bool]
tests2 prefix file0 file1 =
    -- first c0 then c1
    [ runf [file0] (prefix ⊕ "0") True [x1 (f1 c1), f2 c0, f3 c1, f4 c0]
    , runf [file0] (prefix ⊕ "1") False [x1 (f1 c0)]
    , runf [file0] (prefix ⊕ "2") False [x1 d1]
    , runf [file0] (prefix ⊕ "3") False [x1 (f3 c0)]
    , runf [file0] (prefix ⊕ "4") False [x1 d4]

    -- c1 then c0
    , runf [file1] "test-2-5" True [x0 (f1 c0), f2 c0, f3 c0, f4 c0]
    , runf [file1] "test-2-6" False [x0 (f1 c1)]
    , runf [file1] "test-2-7" False [x0 (f2 c1)]
    , runf [file1] "test-2-8" False [x0 (f3 c1)]
    , runf [file1] "test-2-9" False [x0 (f4 c1)]
    ]
  where
    c0 = config0
    c1 = config1
    x0 (ConfAssertion args l v) = ConfAssertion (("--config-file=" ⊕ T.unpack file0):args) l v
    x1 (ConfAssertion args l v) = ConfAssertion (("--config-file=" ⊕ T.unpack file1):args) l v
    runf files = runTest $ mainInfoConfigFile files

-- | Tests with two configuration files
--
tests1 ∷ [T.Text] → [IO Bool]
tests1 files =
    -- first c0 then c1
    [ runf files "test-1-0" True [f1 c1, f2 c0, f3 c1, f4 c0]
    , runf files "test-1-1" False [f1 c0]
    , runf files "test-1-2" False [d1]
    , runf files "test-1-3" False [f3 c0]
    , runf files "test-1-4" False [d4]

    -- c1 then c0
    , runf selif "test-1-5" True [f1 c0, f2 c0, f3 c0, f4 c0]
    , runf selif "test-1-6" False [f1 c1]
    , runf selif "test-1-7" False [f2 c1]
    , runf selif "test-1-8" False [f3 c1]
    , runf selif "test-1-9" False [f4 c1]
    ]
  where
    c0 = config0
    c1 = config1
    selif = reverse files
    runf f = runTest $ mainInfoConfigFile f

-- | Command Line argument test
--
tests0 ∷ [IO Bool]
tests0 =
    [ run "test0" False [d1, d2, d3, d4]

    , run "test1" True [t0, d2, d3, d4]
    , run "test2" True [t1, d2, d3, d4]
    , run "test3" True [d1, t2, d3, d4]
    , run "test4" False [d1, d2, t3, d4]
    , run "test5" False [d1, d2, d3, t4]

    , run "test6" False [t0, t1, d2, d3, d4]
    , run "test7" True [t0, t2, d3, d4]
    , run "test8" True [t0, d2, t3, d4]
    , run "test9" True [t0, d2, d3, t4]
    , run "test10" True [t1, t2, d3, d4]
    , run "test11" True [t1, d2, t3, d4]
    , run "test12" True [t1, d2, d3, t4]
    , run "test13" True [d1, t2, t3, d4]
    , run "test14" True [d1, t2, d3, t4]
    , run "test15" False [d1, d2, t3, t4]

    , run "test16" False [t0, t1, t2, d3, d4]
    , run "test17" False [t0, t1, t3, d4]
    , run "test18" False [t0, t1, d3, t4]
    , run "test19" True [t0, t2, t3, d4]
    , run "test20" True [t0, t2, d3, t4]
    , run "test21" True [t0, d2, t3, t4]
    , run "test22" True [t1, t2, t3, d4]
    , run "test23" True [t1, t2, d3, t4]
    , run "test24" True [t1, d2, t3, t4]
    , run "test25" True [d1, t2, t3, t4]

    , run "test26" False [t0, t1, t2, t3, d4]
    , run "test27" False [t0, t1, t2, d3, t4]
    , run "test28" False [t0, t1, d2, t3, t4]
    , run "test29" True [t0, t2, t3, t4]
    , run "test30" True [t1, t2, t3, t4]

    , run "test31" False [t0, t1, t2, t3, t4]
    ]
  where
    run = runTest mainInfo

-- -------------------------------------------------------------------------- --
-- Test Data

-- | Test configuration 0
--
config0 ∷ HttpURL
config0 = defaultHttpURL
    { _domain = "f0_localhost"
    , _path = "f0_path"
    , _auth = defaultAuth
        { _user = "f0_user"
        , _pwd = "f0_pwd"
        }
    }

-- | Test configuration 1
--
config1 ∷ HttpURL
config1 = defaultHttpURL
    { _domain = "f1_localhost"
    , _path = "f1_path"
    , _auth = defaultAuth
        { _user = "f1_user"
        , _pwd = "f1_pwd"
        }
    }

-- | A partial version of configuration 1
--
config1Part ∷ T.Text
config1Part = T.unlines
    [ "domain: " ⊕ T.pack (view domain config1)
    , "auth:"
    , "    user: " ⊕ T.pack (view (auth ∘ user) config1)
    ]

mainInfo ∷ ProgramInfoValidate HttpURL []
mainInfo = programInfoValidate "HTTP URL" pHttpURL defaultHttpURL validateHttpURL

mainInfoConfigFile
    ∷ [T.Text]
    → ProgramInfoValidate HttpURL []
mainInfoConfigFile files = set piConfigurationFiles files mainInfo

-- -------------------------------------------------------------------------- --
-- Building blocks for tests

-- | Specify a assertion about the parsed configuration
--
-- The parameters are
--
-- 1. list of command line arguments,
-- 2. lens for the configuration value
-- 3. the expected value
--
data ConfAssertion β = ∀ α . Eq α ⇒ ConfAssertion [String] (Lens' β α) α

-- assert values from given configuration

f1 ∷ HttpURL → ConfAssertion HttpURL
f1 conf = ConfAssertion [] domain (view domain conf)

f2 ∷ HttpURL → ConfAssertion HttpURL
f2 conf = ConfAssertion [] path (view path conf)

f3 ∷ HttpURL → ConfAssertion HttpURL
f3 conf = ConfAssertion [] (auth ∘ user) (view (auth ∘ user) conf)

f4 ∷ HttpURL → ConfAssertion HttpURL
f4 conf = ConfAssertion [] (auth ∘ pwd) (view (auth ∘ pwd) conf)

-- assert default values

d1 ∷ ConfAssertion HttpURL
d1 = f1 defaultHttpURL

d2 ∷ ConfAssertion HttpURL
d2 = f2 defaultHttpURL

d3 ∷ ConfAssertion HttpURL
d3 = f3 defaultHttpURL

d4 ∷ ConfAssertion HttpURL
d4 = f4 defaultHttpURL

-- assert values from command line

-- t0 and t1 are the same option
t0 ∷ ConfAssertion HttpURL
t0 = ConfAssertion ["--domain=c_localhost"] domain "c_localhost"

t1 ∷ ConfAssertion HttpURL
t1 = ConfAssertion ["-d", "c_localhost"] domain "c_localhost"

t2 ∷ ConfAssertion HttpURL
t2 = ConfAssertion ["--path=c_abc"] path "c_abc"

t3 ∷ ConfAssertion HttpURL
t3 = ConfAssertion ["--user=c_u"] (auth ∘ user) "c_u"

t4 ∷ ConfAssertion HttpURL
t4 = ConfAssertion ["--pwd=c_pwd"] (auth ∘ pwd) "c_pwd"

-- -------------------------------------------------------------------------- --
-- Test execution

-- Check the given list of assertions for the given configuration value
--
check
    ∷ α
    → [ConfAssertion α]
    → IO Bool
check conf assertions =
    foldM (\a (b,n) → (&& a) <$> go b n) True $ zip assertions [0 ∷ Int ..]
  where
    go (ConfAssertion _ l v) n =
        if view l conf ≡ v
          then do
            debug ∘ T.putStrLn $ "DEBUG: assertion " ⊕ sshow n ⊕ " succeeded"
            return True
          else do
            debug ∘ T.putStrLn $ "DEBUG: assertion " ⊕ sshow n ⊕ " failed"
            return False

-- | Run a test with an expected outcome ('True' or 'False')
-- for a given that of assertions.
--
runTest
    ∷ (FromJSON (α → α), ToJSON α)
    ⇒ ProgramInfoValidate α []
    → T.Text
        -- ^ label for the test case
    → Bool
        -- ^ expected outcome
    → [ConfAssertion α]
        -- ^ test assertions
    → IO Bool
runTest mInfo label succeed assertions = do

    debug ∘ T.putStrLn $ "\nDEBUG: ======> " ⊕ label

    debug ∘ T.putStrLn $ "DEBUG: runWithPkgInfoConfiguration"
    a ← run $ runWithPkgInfoConfiguration mInfo pkgInfo

    debug ∘ T.putStrLn $ "DEBUG: runWithConfiguration"
    b ← run $ runWithConfiguration mInfo

    if a ≡ b && succeed ≡ (a && b)
      then
        return True
      else do
        T.putStrLn $ "WARNING: test " ⊕ label ⊕ " failed"
        return False
  where
    run f = do
        ref ← newIORef False
        handle (handler ref) $ withArgs args ∘ f $ \conf →
            writeIORef ref =<< check conf assertions
        readIORef ref

    args = concatMap (\(ConfAssertion x _ _) → x) assertions

    handler ref (e ∷ SomeException) = do
        writeIORef ref False
        debug ∘ T.putStrLn $ "DEBUG: caugth exception: " ⊕ sshow e

#ifdef REMOTE_CONFIGS
-- -------------------------------------------------------------------------- --
-- Test HTTP server for serving configurations
--

server ∷ Int → IO ()
server port = WARP.run port $ \req respond → do
    let body = LB.fromStrict $ case WAI.pathInfo req of
            ("config0":_) → Yaml.encode $ config0
            ("config1":_) → T.encodeUtf8 $ config1Part
            _ → "invalid: invalid"
    respond $ WAI.responseLBS HTTP.status200 [] body

#endif
