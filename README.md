Overview
========

This package provides a collection of utils on top of the packages
optparse-applicative, aeson, and yaml, for configuring libraries and
applications in a composable way.

The main features are

1.   configuration management through integration of command line option
     parsing and configuration files and
2.   a `Setup.hs` file that generates a `PkgInfo` module that provides
     information about the package and the build.

Configuration Management
========================

The purpose is to make management of configurations easy by providing an
idiomatic style of defining and deploying configurations.

For each data type that is used as a configuration type the following must be
provided:

1.  a default value,

2.  a `FromJSON` instance that yields a function that takes a value and
    updates that value with the parsed values,

3.  a `ToJSON` instance, and

4.  an options parser that yields a function that takes a value and updates
    that value with the values provided as command line options.

The package provides operators and functions that make the implmentation of
these entities easy for the common case that the configurations are encoded
mainly as nested records.

In addition to the user defined command line option the following
options are recognized by the application:

`--config-file, -c`
:    Parse the given file as a (partial) configuration file in YAML format.

`print-config, -p`
:    Print the parsed configuration that would otherwise be used by the
     application to standard out in YAML format and exit.

`--help, -h`
:   Print a help message and exit.

The operators assume that lenses for the configuration record types are
provided.

An complete usage example can be found in the file `example/Example.hs` of the
cabal package.

Usage Example
-------------

Remark: there are unicode equivalents for some operators available in
`Configuration.Utils` that lead to better aligned and more readable code.

We start with some language extensions and imports.

~~~{.haskell}
{-# LANGUAGE UnicodeSyntax #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleInstances #-}

module Main
( main
) where

import Configuration.Utils
import Data.Monoid.Unicode
import Prelude.Unicode
~~~

Next we define types for the configuration of our application. In this contrived
example these are the types for a simplified version of HTTP URLs. We also
derive lenses for the configuration types.

~~~{.haskell}
data Auth = Auth
    { _user :: !String
    , _pwd :: !String
    }

$(makeLenses ''Auth)
~~~

We must provide a default value. If there is no reasonable default the
respective value could for instance be wrapped into `Maybe`.

~~~{.haskell}
defaultAuth :: Auth
defaultAuth = Auth
    { _user = ""
    , _pwd = ""
    }
~~~

Now we define an [Aeson](https://hackage.haskell.org/package/aeson) `FromJSON`
instance that yields a function that updates a given `Auth` value with the
values from the parsed JSON value. The `<.>` operator is functional composition
lifted for applicative functors and `%` is a version of `$` with a different
precedence that helps to reduce the use of paranthesis in applicative style
code.

~~~{.haskell}
instance FromJSON (Auth -> Auth) where
    parseJSON = withObject "Auth" $ \o -> pure id
        <.> user ..: "user" % o
        <.> pwd ..: "pwd" % o
~~~

The `ToJSON` instance is needed to print the configuration (as YAML document)
when the user provides the `--print-config` command line option.

~~~{.haskell}
instance ToJSON Auth where
    toJSON a = object
        [ "user" .= (a ^. user)
        , "pwd" .=  (a ^. pwd)
        ]
~~~

Finally we define a command line option parser using the machinery from
the [optparse-applicative](https://hackage.haskell.org/package/optparse-applicative)
package. Similar to the `FromJSON` instance the parser does not yield a value
directly but instead yields a function that updates a given `Auth` value with
the value from the command line.

~~~{.haskell}
pAuth :: MParser Auth
pAuth = pure id
    <.> user .:: strOption
        % long "user"
        <> help "user name"
    <.> pwd .:: strOption
        % long "pwd"
        <> help "password for user"
~~~

The following definitons for the `HttpURL` are similar to definitions for
the `Auth` type above. In addition it is demonstrated how define nested
configuration types.

~~~{.haskell}
data HttpURL = HttpURL
    { _auth :: !Auth
    , _domain :: !String
    , _path :: !String
    }

$(makeLenses ''HttpURL)

defaultHttpURL :: HttpURL
defaultHttpURL = HttpURL
    { _auth = defaultAuth
    , _domain = ""
    , _path = ""
    }

instance FromJSON (HttpURL -> HttpURL) where
    parseJSON = withObject "HttpURL" $ \o -> pure id
        <.> auth %.: "auth" % o
        <.> domain ..: "domain" % o
        <.> path ..: "path" % o

instance ToJSON HttpURL where
    toJSON a = object
        [ "auth" .= (a ^. auth)
        , "domain" .= (a ^. domain)
        , "path" .= (a ^. path)
        ]

pHttpURL :: MParser HttpURL
pHttpURL = pure id
    <.> auth %:: pAuth
    <.> domain .:: strOption
        % long "domain"
        <> short 'd'
        <> help "HTTP domain"
    <.> path .:: strOption
        % long "path"
        <> short 'p'
        <> help "HTTP URL path"
~~~

Once the configuration value and the related functions and instances is defined
it can be used to create a `ProgramInfo` value. The `ProgramInfo` value is than
use with the `runWithConfiguratin` function to wrap a main function that takes
an `HttpURL` argument with a configuration file and command line parsing.

~~~{.haskell}
mainInfo :: ProgramInfo HttpURL
mainInfo = programInfo "HTTP URL" pHttpURL defaultHttpURL

main :: IO ()
main = runWithConfiguration mainInfo $ \conf -> do
    putStrLn
        $ "http://"
        <> conf ^. auth ∘ user
        <> ":"
        <> conf ^. auth ∘ pwd
        <> "@"
        <> conf ^. domain
        <> "/"
        <> conf ^. path
~~~

Package and Build Information
=============================

The module `Configuration.Utils.Setup` contains an example
`Setup.hs` script that hooks into the cabal build process at the end
of the configuration phase and generates for each a module with package
information for each component of the cabal pacakge.

The modules are created in the *autogen* build directory where also the *Path_*
module is created by cabal's simple build setup. This is usually the directory
`./dist/build/autogen`.

For a library component the module is named just `PkgInfo`. For all
other components the module is name `PkgInfo_COMPONENT_NAME` where
`COMPONENT_NAME` is the name of the component with `-` characters replaced by
`_`.

For instance, if a cabal package contains a library and an executable that
is called *my-app*, the following modules are created: `PkgInfo`
and `PkgInfo_my_app`.

In order to use the feature with your own package the code of the module
`Configuration.Utils.Setup` from the file
`./src/Configuration/Utils/Setup.hs` must be placed into a file called
`Setup.hs` in the root directory of your package. In addition the value of the
`Build-Type` field in the package description (cabal) file must be set to
`Custom`:

    Build-Type: Custom

You can integrate the information provided by the `PkgInfo` modules with the
command line interface of an application by importing the respective module for
the component and using the `runWithPkgInfoConfiguration` function
from the module `Configuration.Utils` as show in the following
example:

~~~{.haskell}
{-# LANGUAGE UnicodeSyntax #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}

module Main
( main
) where

import Configuration.Utils
import PkgInfo

instance FromJSON (() -> ()) where parseJSON _ = pure id

mainInfo :: ProgramInfo ()
mainInfo = programInfo "Hello World" (pure id) ()

main :: IO ()
main = runWithPkgInfoConfiguration mainInfo pkgInfo . const $ putStrLn "hello world"
~~~

With that the resulting application supports the following additional command
line options:

`--version, -v`
:    Print the version of the application and exit.

`--info, -i`
:   Print a short info message for the application and exit.

`--long-info`
:   Print a detailed info message for the application and exit.

`--license`
:   Print the text of the lincense of the application and exit.

Here is the example output of `--long-info` for the example
`examples/Trivial.hs`:

~~~{.shell}
trivial-0.1 (package configuration-tools-0.1 revision f6ec3e5)
Copyright (c) 2014 AlephCloud, Inc.

Author: Lars Kuhtz <lars@alephcloud.com>
License: MIT
Homepage: https://github.com/alephcloud/hs-configuration-tools
Build with: ghc-7.8.2 (x86_64-osx)
Build flags:

Dependencies:
    Cabal-1.21.0.0 (BSD3)
    MonadRandom-0.1.13 (OtherLicense)
    aeson-0.7.0.6 (BSD3)
    ansi-terminal-0.6.1.1 (BSD3)
    ansi-wl-pprint-0.6.7.1 (BSD3)
    array-0.5.0.0 (BSD3)
    attoparsec-0.11.3.4 (BSD3)
    base-4.7.0.0 (BSD3)
    base-unicode-symbols-0.2.2.4 (BSD3)
    bifunctors-4.1.1.1 (BSD3)
    rts-1.0 (BSD3)
    bytestring-0.10.4.0 (BSD3)
    comonad-4.2 (BSD3)
    conduit-1.1.2.1 (MIT)
    containers-0.5.5.1 (BSD3)
    contravariant-0.5.1 (BSD3)
    deepseq-1.3.0.2 (BSD3)
    directory-1.2.1.0 (BSD3)
    distributive-0.4.3.2 (BSD3)
    dlist-0.7.0.1 (BSD3)
    either-4.1.2 (BSD3)
    errors-1.4.7 (BSD3)
    exceptions-0.6.1 (BSD3)
    filepath-1.3.0.2 (BSD3)
    free-4.7.1 (BSD3)
    ghc-prim-0.3.1.0 (BSD3)
    hashable-1.2.2.0 (BSD3)
    integer-gmp-0.5.1.0 (BSD3)
    lens-4.1.2.1 (BSD3)
    lifted-base-0.2.2.2 (BSD3)
    mmorph-1.0.3 (BSD3)
    monad-control-0.3.3.0 (BSD3)
    mtl-2.1.3.1 (BSD3)
    nats-0.2 (BSD3)
    old-locale-1.0.0.6 (BSD3)
    optparse-applicative-0.8.1 (BSD3)
    parallel-3.2.0.4 (BSD3)
    prelude-extras-0.4 (BSD3)
    pretty-1.1.1.1 (BSD3)
    primitive-0.5.3.0 (BSD3)
    process-1.2.0.0 (BSD3)
    profunctors-4.0.4 (BSD3)
    random-1.0.1.1 (BSD3)
    reflection-1.4 (BSD3)
    resourcet-1.1.2.2 (BSD3)
    safe-0.3.4 (BSD3)
    scientific-0.3.2.0 (BSD3)
    semigroupoids-4.0.2 (BSD3)
    semigroups-0.14 (BSD3)
    split-0.2.2 (BSD3)
    syb-0.4.1 (BSD3)
    tagged-0.7.2 (BSD3)
    template-haskell-2.9.0.0 (BSD3)
    text-1.1.1.2 (BSD3)
    time-1.4.2 (BSD3)
    transformers-0.3.0.0 (BSD3)
    transformers-base-0.4.2 (BSD3)
    transformers-compat-0.1.1.1 (BSD3)
    unix-2.7.0.1 (BSD3)
    unordered-containers-0.2.4.0 (BSD3)
    utf8-string-0.3.8 (BSD3)
    vector-0.10.9.1 (BSD3)
    void-0.6.1 (BSD3)
    yaml-0.8.8.3 (BSD3)
    zlib-0.5.4.1 (BSD3)


Available options:
  -i,--info                Print program info message and exit
  --long-info              Print detailed program info message and exit
  -v,--version             Print version string and exit
  --license                Print license of the program and exit
  -h,--help                Show this help text
  -p,--print-config        Print the parsed configuration to standard out and
                           exit
  -c,--config-file FILE    Configuration file for backend services in YAML
                           fromat
~~~

TODO
====

This package is in an early stage of development. I plan to add
more features.

Most of these features are already implemented elsewhere but not yet
integrated into this package.

*   Teach optparse-applicative to not print usage-message for
    info options.

*   Simplify specification of Configuration data types by
    integrating the aeson instances and the option parser.

*   Include help text as comments in YAML serialization of configuration
    values.

*   Provide operators (or at least examples) for more scenarios
    (like required options)

*   Nicer errors messages if parsing fails.

*   Suport JSON encoded configuration files.

*   Support mode where JSON/YAML parsing fails when unexpected
    properties are encountered.

*   Loading of configurations from URLs.

