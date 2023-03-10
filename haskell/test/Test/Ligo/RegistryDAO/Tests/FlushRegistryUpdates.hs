-- SPDX-FileCopyrightText: 2021 Tezos Commons
-- SPDX-License-Identifier: LicenseRef-MIT-TC

module Test.Ligo.RegistryDAO.Tests.FlushRegistryUpdates
  ( flushRegistryUpdates
  ) where

import Prelude

import Test.Tasty (TestTree)

import Lorentz as L hiding (Contract, assert, div)
import Lorentz.Contracts.Spec.FA2Interface qualified as FA2
import Morley.Util.Named
import Test.Cleveland
import Test.Cleveland.Lorentz (contractConsumer)

import Ligo.BaseDAO.RegistryDAO.Types
import Ligo.BaseDAO.Types
import Test.Ligo.BaseDAO.Common
import Test.Ligo.Common
import Test.Ligo.RegistryDAO.Tests.Common
import Test.Ligo.RegistryDAO.Types

flushRegistryUpdates
  :: forall variant. RegistryTestConstraints variant => TestTree
flushRegistryUpdates = testScenario "can flush a transfer proposal with registry updates" $ scenario $
  withOriginated @variant
    (\_ s -> setVariantExtra @variant @"MaxProposalSize" (200 :: Natural) s) $
    \(admin ::< wallet1 ::< wallet2 ::< Nil') (toPeriod -> period) baseDao dodTokenContract -> do

      let
        proposalMeta = toProposalMetadata @variant $ TransferProposal
            1
            [ tokenTransferType (toAddress dodTokenContract) (toAddress wallet2) (toAddress wallet1) ]
            [ ([mt|testKey|], Just [mt|testValue|]) ]
        proposalSize = metadataSize proposalMeta
        proposeParams = ProposeParams (toAddress wallet1) proposalSize proposalMeta

      withSender wallet1 $
        transfer baseDao $ calling (ep @"Freeze") (#amount :! proposalSize)
      withSender wallet2 $
        transfer baseDao $ calling (ep @"Freeze") (#amount :! 50)

      startLevel <- getOriginationLevel' @variant baseDao
      -- Advance one voting period to a proposing stage.
      advanceToLevel (startLevel + period)

      -- We propose the addition of a new registry key *and* a token transfer
      withSender wallet1 $
        transfer baseDao $ calling (ep @"Propose") proposeParams

      checkBalance' @variant baseDao wallet1 proposalSize

      -- Advance one voting period to a voting stage.
      advanceToLevel (startLevel + 2*period)
      -- Then we send 50 upvotes for the proposal (as min quorum is 1% of total frozen tokens)
      let proposalKey = makeProposalKey (ProposeParams (toAddress wallet1) proposalSize proposalMeta)
      withSender wallet2 $
        transfer baseDao $ calling (ep @"Vote") [PermitProtected (VoteParam proposalKey True 50 (toAddress wallet2)) Nothing]

      proposalStart <- getProposalStartLevel' @variant baseDao proposalKey
      advanceToLevel (proposalStart + 2*period)
      withSender admin $ transfer baseDao $ calling (ep @"Flush") (1 :: Natural)

      -- check the registry update
      consumer <- originate "consumer" [] (contractConsumer @(MText, (Maybe MText)))
      withSender wallet2 $ transfer baseDao $
        calling (ep @"Lookup_registry") $
          LookupRegistryParam [mt|testKey|] $ toAddress consumer
      checkStorage consumer ([([mt|testKey|], Just [mt|testValue|])])

      -- check the balance
      checkBalance' @variant baseDao wallet1 proposalSize
      checkBalance' @variant baseDao wallet2 50

      checkStorage dodTokenContract
        [ [ FA2.TransferItem { tiFrom = (toAddress wallet2), tiTxs = [FA2.TransferDestination { tdTo = toAddress wallet1 , tdTokenId = FA2.theTokenId, tdAmount = 10 }] } ] -- Actual transfer
          , [ FA2.TransferItem { tiFrom = (toAddress wallet2), tiTxs = [FA2.TransferDestination { tdTo = toAddress baseDao, tdTokenId = FA2.theTokenId, tdAmount = 50 }] } ] -- Wallet2 freezes 50 tokens
          , [ FA2.TransferItem { tiFrom = (toAddress wallet1), tiTxs = [FA2.TransferDestination { tdTo = toAddress baseDao, tdTokenId = FA2.theTokenId, tdAmount = proposalSize }] } ] -- governance token transfer for freeze
        ]
