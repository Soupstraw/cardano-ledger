{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Cardano.Ledger.ShelleyMA.Rules.Utxow (UTXOW) where

import Cardano.Ledger.BaseTypes
import Cardano.Ledger.Core
import Cardano.Ledger.Shelley.LedgerState (UTxOState)
import qualified Cardano.Ledger.Shelley.Rules.Ledger as Shelley
import Cardano.Ledger.Shelley.Rules.Utxo (UtxoEnv)
import Cardano.Ledger.Shelley.Rules.Utxow
  ( ShelleyStyleWitnessNeeds,
    UtxowEvent (..),
    UtxowPredicateFailure (..),
    transitionRulesUTXOW,
  )
import Cardano.Ledger.Shelley.Tx (ShelleyWitnesses)
import Cardano.Ledger.Shelley.TxBody (ShelleyEraTxBody)
import Cardano.Ledger.ShelleyMA.Era (UTXOW)
import Cardano.Ledger.ShelleyMA.Rules.Utxo (UTXO, UtxoPredicateFailure)
import Control.State.Transition.Extended

-- ==============================================================================
--   We want to reuse the same rules for Mary and Allegra. We accomplish this
--   by adding: HasField "minted" (TxBody era) (Set (ScriptHash (Crypto era)))
--   to the (WellFormed era) constraint, and adjusting UTxO.(ScriptsNeeded) to
--   add this set to its output. In the Shelley and Allegra Era, this is the empty set.
--   With this generalization, Cardano.Ledger.Shelley.Rules.Utxow(shelleyStyleWitness)
--   can still be used in Allegra and Mary, because they use the same Shelley style rules.

--------------------------------------------------------------------------------
-- UTXOW STS
--------------------------------------------------------------------------------

instance
  forall era.
  ( EraTx era,
    ShelleyEraTxBody era,
    Witnesses era ~ ShelleyWitnesses era,
    -- Allow UTXOW to call UTXO
    Embed (EraRule "UTXO" era) (UTXOW era),
    Environment (EraRule "UTXO" era) ~ UtxoEnv era,
    State (EraRule "UTXO" era) ~ UTxOState era,
    Signal (EraRule "UTXO" era) ~ Tx era,
    -- Supply the HasField and Validate instances for Mary and Allegra (which match Shelley)
    ShelleyStyleWitnessNeeds era
  ) =>
  STS (UTXOW era)
  where
  type State (UTXOW era) = UTxOState era
  type Signal (UTXOW era) = Tx era
  type Environment (UTXOW era) = UtxoEnv era
  type BaseM (UTXOW era) = ShelleyBase
  type PredicateFailure (UTXOW era) = UtxowPredicateFailure era
  type Event (UTXOW era) = UtxowEvent era

  transitionRules = [transitionRulesUTXOW]

  -- The ShelleyMA Era uses the same PredicateFailure type
  -- as Shelley, so the 'embed' function is identity
  initialRules = []

instance
  ( Era era,
    STS (UTXO era),
    PredicateFailure (EraRule "UTXO" era) ~ UtxoPredicateFailure era,
    Event (EraRule "UTXO" era) ~ Event (UTXO era)
  ) =>
  Embed (UTXO era) (UTXOW era)
  where
  wrapFailed = UtxoFailure
  wrapEvent = UtxoEvent

instance
  ( Era era,
    STS (UTXOW era),
    PredicateFailure (EraRule "UTXOW" era) ~ UtxowPredicateFailure era,
    Event (EraRule "UTXOW" era) ~ Event (UTXOW era)
  ) =>
  Embed (UTXOW era) (Shelley.LEDGER era)
  where
  wrapFailed = Shelley.UtxowFailure
  wrapEvent = Shelley.UtxowEvent
