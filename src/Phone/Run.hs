{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
-- |
-- Module:       $HEADER$
-- Description:  Low level FFI.
-- Copyright:
-- License:      GPL-2
--
-- Maintainer:   Jan Sipr <jan.sipr@ixperta.com>
-- Stability:    experimental
-- Portability:  GHC specific language extensions.
module Phone.Run
    ( withPhone
    , setNullSndDev
    )
  where

import Control.Applicative (pure)
import Control.Exception.Base (bracket_, throwIO)
import Control.Monad ((>=>), (>>=), void)
import Data.Eq ((/=))
import Data.Function (($), (.))
import Data.Maybe (maybe)
import Foreign.Ptr (nullPtr)
import Prelude (fromIntegral)
import System.IO (IO)

import Phone.Exception
    ( PhoneException
        ( CreateLib
        , Initialization
        , Start
        , Transport
        )
    )
import Phone.Handlers
    ( Handlers
        ( Handlers
        , onCallStateChange
        , onIncomingCall
        , onMediaStateChange
        , onRegistrationStarted
        , onRegistrationStateChange
        )
    )
import Phone.Internal.FFI (createPjSua, destroyPjSua, pjsuaStart, setNullSndDev, codecSetPriority)
import Phone.Internal.FFI.CallManipulation (hangupAll)
import Phone.Internal.FFI.Common (pjSuccess, pjFalse)
import Phone.Internal.FFI.Configuration
    ( initializePjSua
    , setOnCallStateCallback
    , setOnIncomingCallCallback
    , setOnMediaStateCallback
    , setOnRegistrationStartedCallback
    , setOnRegistrationStateCallback
    , toOnCallState
    , toOnIncomingCall
    , toOnMediaState
    , toOnRegistrationStarted
    , toOnRegistrationState
    , withPjConfig
    )
import Phone.Internal.FFI.Logging
    ( withLoggingConfig
    , setLogFilename
    , setMsgLogging
    -- , setConsoleLevel
    )
import Phone.Internal.FFI.Media (withMediaConfig, setMediaConfigClockRate)
import Phone.Internal.FFI.PjString (withPjString, withPjStringPtr)
import Phone.Internal.FFI.Transport
    ( createTransport
    , udpTransport
    , withTransportConfig
    )

withPhone :: Handlers -> IO () -> IO ()
withPhone Handlers{..} = bracket_ initSeq deinitSeq
  where
    initSeq = do
        createPjSua >>= check CreateLib
        withPjConfig $ \pjCfg -> do
            maybeHandler onCallStateChange
                ((toOnCallState . onCallState) >=> setOnCallStateCallback pjCfg)
            maybeHandler onIncomingCall
                ((toOnIncomingCall . onIncCall)
                >=> setOnIncomingCallCallback pjCfg)
            maybeHandler onRegistrationStateChange
                (toOnRegistrationState >=> setOnRegistrationStateCallback pjCfg)
            maybeHandler onRegistrationStarted
                ((toOnRegistrationStarted . onRegStarted)
                >=> setOnRegistrationStartedCallback pjCfg)
            maybeHandler onMediaStateChange
                (toOnMediaState >=> setOnMediaStateCallback pjCfg)
            withLog $ \logCfg ->
                withMedia $ \mediaCfg ->
                    initializePjSua pjCfg logCfg mediaCfg >>= check Initialization
        withTransportConfig $ \transportCfg ->
            createTransport udpTransport transportCfg nullPtr >>= check Transport
        pjsuaStart >>= check Start
        setCodecs

    withLog f =
        withPjString "pjsua_log.txt" $ \logFile -> -- FIXME: hardcoded
        withLoggingConfig $ \logCfg -> do
            setMsgLogging logCfg pjFalse
            setLogFilename logCfg logFile
            f logCfg

    withMedia f =
        withMediaConfig $ \mediaCfg -> do
            -- When pjproject is built without resampling (as it happens to be
            -- in Debian), we want to fix the rate and codecs so that we don't
            -- crash in resampler creation.
            setMediaConfigClockRate mediaCfg 8000
            f mediaCfg

    setCodecs = do
        withPjStringPtr "PCMU" $ \codecStr -> codecSetPriority codecStr 255
        withPjStringPtr "PCMA" $ \codecStr -> codecSetPriority codecStr 255

    onCallState f callId _ = f callId
    onIncCall f acc callId _ = f acc callId
    onRegStarted f acc p = f acc $ fromIntegral p

    deinitSeq = do
        hangupAll
        void destroyPjSua

    check e ret = if ret /= pjSuccess
        then throwIO e
        else pure ()

    maybeHandler m op = maybe (pure ()) op m
