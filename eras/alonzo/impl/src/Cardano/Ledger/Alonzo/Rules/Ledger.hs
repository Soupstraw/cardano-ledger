{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Cardano.Ledger.Alonzo.Rules.Ledger
  ( AlonzoLEDGER,
    ledgerTransition,
  )
where

import Cardano.Ledger.Alonzo.Era (AlonzoLEDGER)
import Cardano.Ledger.Alonzo.Rules.Utxow (AlonzoUtxowEvent, AlonzoUTXOW, UtxowPredicateFail)
import Cardano.Ledger.Alonzo.Tx (AlonzoEraTx (..), AlonzoTx (..), IsValid (..))
import Cardano.Ledger.Alonzo.TxBody (ShelleyEraTxBody (..))
import Cardano.Ledger.BaseTypes (ShelleyBase)
import Cardano.Ledger.Coin (Coin)
import Cardano.Ledger.Core
import Cardano.Ledger.Keys (DSignable, Hash)
import Cardano.Ledger.Shelley.EpochBoundary (obligation)
import Cardano.Ledger.Shelley.LedgerState
  ( DPState (..),
    DState (..),
    LedgerState (..),
    PState (..),
    UTxOState (..),
    rewards,
  )
import Cardano.Ledger.Shelley.Rules.Delegs
  ( DELEGS,
    DelegsEnv (..),
    DelegsEvent,
    DelegsPredicateFailure,
  )
import Cardano.Ledger.Shelley.Rules.Ledger
  ( LedgerEnv (..),
    LedgerEvent (..),
    LedgerPredicateFailure (..),
  )
import qualified Cardano.Ledger.Shelley.Rules.Ledgers as Shelley
import Cardano.Ledger.Shelley.Rules.Utxo
  ( UtxoEnv (..),
  )
import Cardano.Ledger.Shelley.TxBody (DCert)
import Control.State.Transition
  ( Assertion (..),
    AssertionViolation (..),
    Embed (..),
    STS (..),
    TRC (..),
    TransitionRule,
    judgmentContext,
    trans,
  )
import Data.Kind (Type)
import Data.Sequence (Seq)
import qualified Data.Sequence.Strict as StrictSeq
import GHC.Records (HasField)
import Lens.Micro

-- =======================================

-- | An abstract Alonzo Era, Ledger transition. Fix 'someLedger' at a concrete type to
--   make it concrete.
ledgerTransition ::
  forall (someLEDGER :: Type -> Type) era.
  ( Signal (someLEDGER era) ~ Tx era,
    State (someLEDGER era) ~ LedgerState era,
    Environment (someLEDGER era) ~ LedgerEnv era,
    Embed (EraRule "UTXOW" era) (someLEDGER era),
    Embed (EraRule "DELEGS" era) (someLEDGER era),
    Environment (EraRule "DELEGS" era) ~ DelegsEnv era,
    State (EraRule "DELEGS" era) ~ DPState (Crypto era),
    Signal (EraRule "DELEGS" era) ~ Seq (DCert (Crypto era)),
    Environment (EraRule "UTXOW" era) ~ UtxoEnv era,
    State (EraRule "UTXOW" era) ~ UTxOState era,
    Signal (EraRule "UTXOW" era) ~ Tx era,
    AlonzoEraTx era
  ) =>
  TransitionRule (someLEDGER era)
ledgerTransition = do
  TRC (LedgerEnv slot txIx pp account, LedgerState utxoSt dpstate, tx) <- judgmentContext
  let txBody = tx ^. bodyTxL

  dpstate' <-
    if tx ^. isValidTxL == IsValid True
      then
        trans @(EraRule "DELEGS" era) $
          TRC
            ( DelegsEnv slot txIx pp tx account,
              dpstate,
              StrictSeq.fromStrict $ txBody ^. certsTxBodyL
            )
      else pure dpstate

  let DPState dstate pstate = dpstate
      genDelegs = _genDelegs dstate
      stpools = _pParams pstate

  utxoSt' <-
    trans @(EraRule "UTXOW" era) $
      TRC
        ( UtxoEnv @era slot pp stpools genDelegs,
          utxoSt,
          tx
        )
  pure $ LedgerState utxoSt' dpstate'

instance
  ( Show (Script era), -- All these Show instances arise because
    Show (TxBody era), -- renderAssertionViolation, turns them into strings
    Show (TxOut era),
    Show (State (EraRule "PPUP" era)),
    Show (AuxiliaryData era),
    Show (PParams era),
    Show (Value era),
    Show (PParamsUpdate era),
    DSignable (Crypto era) (Hash (Crypto era) EraIndependentTxBody),
    AlonzoEraTx era,
    Tx era ~ AlonzoTx era,
    Embed (EraRule "DELEGS" era) (AlonzoLEDGER era),
    Embed (EraRule "UTXOW" era) (AlonzoLEDGER era),
    Environment (EraRule "UTXOW" era) ~ UtxoEnv era,
    State (EraRule "UTXOW" era) ~ UTxOState era,
    Signal (EraRule "UTXOW" era) ~ AlonzoTx era,
    Environment (EraRule "DELEGS" era) ~ DelegsEnv era,
    State (EraRule "DELEGS" era) ~ DPState (Crypto era),
    Signal (EraRule "DELEGS" era) ~ Seq (DCert (Crypto era)),
    HasField "_keyDeposit" (PParams era) Coin,
    HasField "_poolDeposit" (PParams era) Coin
  ) =>
  STS (AlonzoLEDGER era)
  where
  type State (AlonzoLEDGER era) = LedgerState era
  type Signal (AlonzoLEDGER era) = AlonzoTx era
  type Environment (AlonzoLEDGER era) = LedgerEnv era
  type BaseM (AlonzoLEDGER era) = ShelleyBase
  type PredicateFailure (AlonzoLEDGER era) = LedgerPredicateFailure era
  type Event (AlonzoLEDGER era) = LedgerEvent era

  initialRules = []
  transitionRules = [ledgerTransition @AlonzoLEDGER]

  renderAssertionViolation AssertionViolation {avSTS, avMsg, avCtx, avState} =
    "AssertionViolation (" <> avSTS <> "): " <> avMsg
      <> "\n"
      <> show avCtx
      <> "\n"
      <> show avState

  assertions =
    [ PostCondition
        "Deposit pot must equal obligation"
        ( \(TRC (LedgerEnv {ledgerPp}, _, _))
           (LedgerState utxoSt DPState {dpsDState, dpsPState}) ->
              obligation ledgerPp (rewards dpsDState) (_pParams dpsPState)
                == _deposited utxoSt
        )
    ]

instance
  ( Era era,
    STS (DELEGS era),
    PredicateFailure (EraRule "DELEGS" era) ~ DelegsPredicateFailure era,
    Event (EraRule "DELEGS" era) ~ DelegsEvent era
  ) =>
  Embed (DELEGS era) (AlonzoLEDGER era)
  where
  wrapFailed = DelegsFailure
  wrapEvent = DelegsEvent

instance
  ( Era era,
    STS (AlonzoUTXOW era),
    PredicateFailure (EraRule "UTXOW" era) ~ UtxowPredicateFail era,
    Event (EraRule "UTXOW" era) ~ AlonzoUtxowEvent era
  ) =>
  Embed (AlonzoUTXOW era) (AlonzoLEDGER era)
  where
  wrapFailed = UtxowFailure
  wrapEvent = UtxowEvent

instance
  ( Era era,
    STS (AlonzoLEDGER era),
    PredicateFailure (EraRule "LEDGER" era) ~ LedgerPredicateFailure era,
    Event (EraRule "LEDGER" era) ~ LedgerEvent era
  ) =>
  Embed (AlonzoLEDGER era) (Shelley.LEDGERS era)
  where
  wrapFailed = Shelley.LedgerFailure
  wrapEvent = Shelley.LedgerEvent
