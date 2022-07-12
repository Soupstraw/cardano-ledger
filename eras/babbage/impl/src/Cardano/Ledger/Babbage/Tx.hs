{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Cardano.Ledger.Babbage.Tx
  ( BabbageTxBody (..),
  )
where

import Cardano.Ledger.Alonzo.Tx as X hiding (AlonzoTxBody, TxBody)
import Cardano.Ledger.Alonzo.TxSeq
  ( AlonzoTxSeq (AlonzoTxSeq, txSeqTxns),
    hashAlonzoTxSeq,
  )
import Cardano.Ledger.Alonzo.TxWitness
  ( AlonzoEraWitnesses (..),
    TxWitness (..),
    addrAlonzoWitsL,
    bootAddrAlonzoWitsL,
    datsAlonzoWitsL,
    rdmrsAlonzoWitsL,
    scriptAlonzoWitsL,
  )
import Cardano.Ledger.Babbage.Era (BabbageEra)
import Cardano.Ledger.Babbage.TxBody (BabbageTxBody (..))
import Cardano.Ledger.Core
import qualified Cardano.Ledger.Crypto as CC

instance CC.Crypto c => EraTx (BabbageEra c) where
  type Tx (BabbageEra c) = AlonzoTx (BabbageEra c)
  mkBasicTx = mkBasicAlonzoTx
  bodyTxL = bodyAlonzoTxL
  witsTxL = witsAlonzoTxL
  auxDataTxL = auxDataAlonzoTxL
  sizeTxG = sizeAlonzoTxG

instance CC.Crypto c => AlonzoEraTx (BabbageEra c) where
  isValidTxL = isValidAlonzoTxL

instance CC.Crypto c => EraWitnesses (BabbageEra c) where
  type Witnesses (BabbageEra c) = TxWitness (BabbageEra c)
  mkBasicWitnesses = mempty
  addrWitsL = addrAlonzoWitsL
  bootAddrWitsL = bootAddrAlonzoWitsL
  scriptWitsL = scriptAlonzoWitsL

instance CC.Crypto c => AlonzoEraWitnesses (BabbageEra c) where
  datsWitsL = datsAlonzoWitsL
  rdmrsWitsL = rdmrsAlonzoWitsL

instance CC.Crypto c => SupportsSegWit (BabbageEra c) where
  type TxSeq (BabbageEra c) = AlonzoTxSeq (BabbageEra c)
  fromTxSeq = txSeqTxns
  toTxSeq = AlonzoTxSeq
  hashTxSeq = hashAlonzoTxSeq
  numSegComponents = 4
