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
        , Initializeation
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
import Phone.Internal.FFI (createPjSua, destroyPjSua, pjsuaStart)
import Phone.Internal.FFI.CallManipulation (hangupAll)
import Phone.Internal.FFI.Common (pjSuccess)
import Phone.Internal.FFI.Configuration
    ( createPjConfig
    , defaultPjConfig
    , initializePjSua
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
    )
import Phone.Internal.FFI.Media (createMediaConfig, defaultMedaiConfig)
import Phone.Internal.FFI.Transport
    ( createTransport
    , createTransportConfig
    , udpTransport
    )

withPhone :: Handlers -> IO () -> IO ()
withPhone Handlers{..} op = bracket_ initSeq deinitSeq op
  where
    initSeq = do
        createPjSua >>= check CreateLib
        pjCfg <- createPjConfig
        defaultPjConfig pjCfg
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
        mediaCfg <- createMediaConfig
        defaultMedaiConfig mediaCfg
        initializePjSua pjCfg nullPtr mediaCfg >>= check Initializeation
        transportCfg <- createTransportConfig
        createTransport udpTransport transportCfg nullPtr >>= check Transport
        pjsuaStart >>= check Start

    onCallState f callId _ = f callId
    onIncCall f acc callId _ = f acc callId
    onRegStarted f acc p = f acc $ fromIntegral p

    deinitSeq = do
        hangupAll
        void destroyPjSua

    check e ret = if ret /= pjSuccess
        then throwIO e
        else pure ()

    maybeHandler m op' = maybe (pure ()) op' m