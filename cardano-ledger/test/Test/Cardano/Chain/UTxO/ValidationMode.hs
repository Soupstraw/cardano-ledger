{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Test.Cardano.Chain.UTxO.ValidationMode
  ( tests
  )
where

import Cardano.Prelude
import Test.Cardano.Prelude

import qualified Data.ByteString as BS
import qualified Data.Map.Strict as M
import qualified Data.Vector as V

import Cardano.Binary (Annotated (..))
import Cardano.Chain.Common
  ( TxFeePolicy (..)
  , calculateTxSizeLinear
  , lovelaceToInteger
  )
import Cardano.Chain.Update (ProtocolParameters (..))
import Cardano.Chain.UTxO
  ( ATxAux (..)
  , Environment (..)
  , TxId
  , TxValidationError (..)
  , TxValidationMode (..)
  , UTxOValidationError (..)
  )
import qualified Cardano.Chain.UTxO as UTxO
import Cardano.Crypto (getProtocolMagicId)

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import qualified Ledger.Core as Abstract
import qualified Ledger.Core.Generators as Abstract
import qualified Ledger.Update as Abstract
import qualified Ledger.Update.Generators as Abstract
import qualified Ledger.UTxO as Abstract
import qualified Ledger.UTxO.Generators as Abstract

import Test.Cardano.Chain.Elaboration.Update (elaboratePParams)
import Test.Cardano.Chain.Elaboration.UTxO (elaborateTxWitsBS)
import Test.Cardano.Chain.UTxO.Gen (genVKWitness)
import Test.Cardano.Chain.UTxO.Model (elaborateInitialUTxO)
import qualified Test.Cardano.Crypto.Dummy as Dummy
import Test.Options (TSGroup, TSProperty, withTestsTS)

--------------------------------------------------------------------------------
-- TxValidationMode Properties
--------------------------------------------------------------------------------

-- | Property: When calling 'updateUTxO' given a valid transaction, 'UTxO'
-- validation should pass in all 'TxValidationMode's.
ts_prop_updateUTxO_Valid :: TSProperty
ts_prop_updateUTxO_Valid =
  withTestsTS 300
    . property
    $ do
      -- Generate abstract `PParamsAddrsAndUTxO`
      ppau@(PParamsAddrsAndUTxO abstractPparams _ abstractUtxo) <-
        forAll $ genPParamsAddrsAndUTxO (Range.constant 1 5)

      -- Elaborate abstract values to concrete.
      let pparams = elaboratePParams abstractPparams
          (utxo, txIdMap) = elaborateInitialUTxO abstractUtxo

      -- Generate abstract transaction and elaborate.
      abstractTxWits <- forAll $ genValidTxWits ppau txIdMap
      let tx = elaborateTxWitsBS
            (elaborateTxId txIdMap)
            abstractTxWits

      -- Validate the generated concrete transaction
      let pm = Dummy.aProtocolMagic
          env = Environment pm pparams
      tvmode <- forAll $ genValidationMode
      case UTxO.updateUTxO tvmode env utxo [tx] of
        Left _  -> failure
        Right _ -> success

-- | Property: When calling 'updateUTxO' given a valid transaction with an
-- invalid witness, 'UTxO' validation should pass in both the
-- 'TxValidationNoCrypto' and 'NoTxValidation' modes. This is because neither
-- of these modes verify the cryptographic integrity of a transaction.
ts_prop_updateUTxO_InvalidWit :: TSProperty
ts_prop_updateUTxO_InvalidWit =
  withTestsTS 300
    . property
    $ do
      -- Generate abstract `PParamsAddrsAndUTxO`
      ppau@(PParamsAddrsAndUTxO abstractPparams _ abstractUtxo) <-
        forAll $ genPParamsAddrsAndUTxO (Range.constant 1 5)

      -- Elaborate abstract values to concrete.
      let pparams = elaboratePParams abstractPparams
          (utxo, txIdMap) = elaborateInitialUTxO abstractUtxo

      -- Generate abstract transaction and elaborate.
      abstractTxWits <- forAll $ genValidTxWits ppau txIdMap
      let tx = elaborateTxWitsBS
            (elaborateTxId txIdMap)
            abstractTxWits

      -- Generate an invalid 'TxWitness' and utilize it in the valid
      -- transaction generated above.
      let pm = Dummy.aProtocolMagic
      invalidWitness <- forAll $
        Annotated
          <$> (V.fromList
                <$> Gen.list (Range.linear 1 10)
                             (genVKWitness (getProtocolMagicId pm))
              )
          <*> genBytes 32
      let txInvalidWit = tx { aTaWitness = invalidWitness }

      -- Validate the generated concrete transaction
      let env = Environment pm pparams
      tvmode <- forAll $ genValidationMode
      case UTxO.updateUTxO tvmode env utxo [txInvalidWit] of
        Left err -> if isInvalidWitnessError err && tvmode == TxValidation
                    then success
                    else failure
        Right _ -> if tvmode == TxValidation then failure else success
 where
  isInvalidWitnessError :: UTxOValidationError -> Bool
  isInvalidWitnessError (UTxOValidationTxValidationError err) = case err of
    TxValidationInvalidWitness _ -> True
    _ -> False
  isInvalidWitnessError _ = False

--------------------------------------------------------------------------------
-- Generators
--------------------------------------------------------------------------------

genAbstractAddrs :: Range Int -> Gen [Abstract.Addr]
genAbstractAddrs r = Gen.list r Abstract.addrGen

genInitialAbstractUTxO :: [Abstract.Addr] -> Gen Abstract.UTxO
genInitialAbstractUTxO addrs =
  Abstract.fromTxOuts <$> Abstract.genInitialTxOuts addrs

genPParamsAddrsAndUTxO
  :: Range Int
  -- ^ Range for generation of 'Abstract.Addr's.
  -> Gen PParamsAddrsAndUTxO
genPParamsAddrsAndUTxO addrRange = do
  abstractPparams <- Abstract.pparamsGen
  abstractAddrs <- genAbstractAddrs addrRange
  abstractUtxo <- genInitialAbstractUTxO abstractAddrs
  pure $ PParamsAddrsAndUTxO abstractPparams abstractAddrs abstractUtxo

genValidTxWits
  :: PParamsAddrsAndUTxO
  -> Map Abstract.TxId TxId
  -> Gen Abstract.TxWits
genValidTxWits ppau txIdMap = do
  abstractTx <- Abstract.genTxFromUTxO
    ppauAddrs
    (abstractTxFee txIdMap (ppTxFeePolicy pparams) ppauUTxO)
    ppauUTxO
  pure $ Abstract.makeTxWits ppauUTxO abstractTx
 where
  PParamsAddrsAndUTxO
    { ppauPParams
    , ppauAddrs
    , ppauUTxO
    } = ppau

  pparams = elaboratePParams ppauPParams

genValidationMode :: Gen TxValidationMode
genValidationMode = Gen.element
  [ TxValidation
  , TxValidationNoCrypto
  , NoTxValidation
  ]

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

data PParamsAddrsAndUTxO = PParamsAddrsAndUTxO
  { ppauPParams :: !Abstract.PParams
  , ppauAddrs   :: ![Abstract.Addr]
  , ppauUTxO    :: !Abstract.UTxO
  } deriving (Show)

-- | Elaborate an 'Abstract.Tx', calculate the 'Concrete.Lovelace' fee, then
-- convert back to an 'Abstract.Lovelace'.
-- n.b. Calculating the fee with 'Abstract.pcMinFee', for example, proved to
-- be ineffective as it utilizes the 'Abstract.Size' of the 'Abstract.Tx' in
-- its calculation when we really need to take into account the actual
-- concrete size in bytes.
abstractTxFee
  :: Map Abstract.TxId UTxO.TxId
  -> TxFeePolicy
  -> Abstract.UTxO
  -> Abstract.Tx
  -> Abstract.Lovelace
abstractTxFee txIdMap tfp aUtxo aTx = do
  let aTxWits = Abstract.makeTxWits aUtxo aTx
      ATxAux (Annotated _ txBytes) _ = elaborateTxWitsBS
        (elaborateTxId txIdMap)
        aTxWits
      cLovelace = case tfp of
        TxFeePolicyTxSizeLinear txSizeLinear ->
          either (panic . show)
                  (\x -> x)
                  (calculateTxSizeLinear
                    txSizeLinear
                    (fromIntegral $ BS.length txBytes))
  Abstract.Lovelace (lovelaceToInteger cLovelace)

elaborateTxId :: Map Abstract.TxId UTxO.TxId -> Abstract.TxId -> TxId
elaborateTxId txIdMap abstractTxId =
  case M.lookup abstractTxId txIdMap of
    Nothing -> panic "elaborateTxId: Missing abstract TxId during elaboration"
    Just x  -> x

--------------------------------------------------------------------------------
-- Main Test Export
--------------------------------------------------------------------------------

tests :: TSGroup
tests = $$discoverPropArg
