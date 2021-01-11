-- SPDX-FileCopyrightText: 2020 TQ Tezos
-- SPDX-License-Identifier: LicenseRef-MIT-TQ

module Lorentz.Contracts.BaseDAO
  ( Config(..)
  , defaultConfig

  , Ledger
  , Operators
  , Parameter (..)
  , Storage (..)

  , DaoContract
  , DaoC
  , baseDaoContract
  , mkStorage

  , knownBaseDAOMetadata
  ) where

import Lorentz
import Universum (Each)

import Lorentz.Contracts.BaseDAO.Doc
import Lorentz.Contracts.BaseDAO.Management
import Lorentz.Contracts.BaseDAO.Proposal
import Lorentz.Contracts.BaseDAO.Token
import Lorentz.Contracts.BaseDAO.Token.FA2
import Lorentz.Contracts.BaseDAO.Types as BaseDAO
import Lorentz.Contracts.BaseDAO.TZIP16Metadata
import qualified Lorentz.Contracts.Spec.FA2Interface as FA2
import Michelson.Optimizer (OptimizerConf (..))

data FA2EntrypointsKind
instance EntrypointKindHasDoc FA2EntrypointsKind where
  entrypointKindPos = 1055
  entrypointKindSectionName = "FA2 entrypoints"

type DaoContract ce pm op =
  Contract (BaseDAO.Parameter pm op) (BaseDAO.Storage ce pm)

type DaoC ce pm op =
  ( NiceParameterFull (Parameter pm op), NiceStorage (Storage ce pm)
  , Each [IsoValue, HasAnnotation, TypeHasDoc] [pm, op]
  , NicePackedValue pm
  , KnownValue ce, TypeHasDoc ce
  )

baseDaoContract
  :: forall ce pm op. DaoC ce pm op
  => Config ce pm op -> DaoContract ce pm op
baseDaoContract config@Config{..} = optimizeBetter $ defaultContract $ contractName cDaoName $ do
  contractGeneralDefault
  doc $ DDescription $ cDaoDescription <> "\n\n" <> introductoryDoc
  docStorage @(BaseDAO.Storage ce pm)

  -- TODO: [#91] Disabled for now due to unable to send XTZ
  -- entrypointSection "Prior checks" (Proxy @CommonContractBehaviourKind) $ do
  --   doc $ DDescription priorChecksDoc
  --   ensureZeroTransfer

  pushFuncContext @ce @pm $ do
    unpair
    finalizeParamCallingDoc $ entryCase @(BaseDAO.Parameter pm op) (Proxy @PlainEntrypointsKind)
      ( #cAccept_ownership /-> acceptOwnership
      , #cBurn /-> burn
      , #cCall_FA2 /-> fa2Handler
      , #cCallCustom /-> do
          doc $ DDescription callCustomDoc
          cCustomCall # pair
      , #cConfirm_migration /-> confirmMigration
      , #cDrop_proposal /-> dropProposal config
      , #cFlush /-> flush config
      , #cGetVotePermitCounter /-> view_ $ do
          doc $ DDescription getVotePermitCounterDoc
          drop @(); stToField #sPermitsCounter
      , #cMigrate /-> migrate
      , #cMint /-> mint
      , #cPropose /-> propose config
      , #cSet_quorum_threshold /-> setQuorumThreshold config
      , #cSet_voting_period /-> setVotingPeriod config
      , #cTransfer_contract_tokens /-> transferContractTokens
      , #cTransfer_ownership /-> transferOwnership
      , #cVote /-> vote config
      )
  where
    -- By default we insert the CAST instruction at the beginning of
    -- the contract and do not optimize lambdas in code.
    -- In our case CAST is redundant and optimizing lambdas is harmless, so
    -- let's do it.
    optimizeBetter :: Contract cp st -> Contract cp st
    optimizeBetter c = c
      { cDisableInitialCast = True
      , cCompilationOptions = (cCompilationOptions c)
        { coOptimizerConf = Just $ def {gotoValues = True}
        }
      }

fa2Handler
  :: (IsoValue ce, KnownValue pm, HasFuncContext s (BaseDAO.Storage ce pm))
  => Entrypoint' FA2.Parameter (BaseDAO.Storage ce pm) s
fa2Handler = do
  doc $ DDescription callFA2Doc
  entryCase @FA2.Parameter (Proxy @FA2EntrypointsKind)
    ( #cTransfer /-> transfer
    , #cBalance_of /-> balanceOf
    , #cToken_metadata_registry /-> tokenMetadataRegistry
    , #cUpdate_operators /-> updateOperators
    )

-- TODO: [#91] Disabled for now due to unable to send XTZ
-- ensureZeroTransfer :: s :-> s
-- ensureZeroTransfer = do
--   amount
--   push zeroMutez
--   if IsEq then nop else failCustom_ #fORBIDDEN_XTZ

pushFuncContext
  :: (KnownValue ce, KnownValue pm)
  => (forall s. HasFuncContext s (BaseDAO.Storage ce pm) =>
      (inp : s) :-> (out : s)
     )
  -> Lambda inp out
pushFuncContext action = do
  dip $ do
    pushCachedFunc creditTo
    pushCachedFunc debitFrom
  action
  dip $ dropN @2
