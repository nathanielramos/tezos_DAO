-- SPDX-FileCopyrightText: 2021 TQ Tezos
-- SPDX-License-Identifier: LicenseRef-MIT-TQ

-- | TZIP-16 metadata.
module Ligo.BaseDAO.TZIP16Metadata
  ( MetadataConfig (..)
  , MetadataSettings (..)
  , defaultMetadataConfig
  , knownBaseDAOMetadata
  , mkMetadataSettings

  , baseDAOViews
  , getBalanceView
  , allTokensView
  , isOperatorView
  , tokenMetadataView
  , getTotalSupplyView
  , permitsCounterView
  ) where

import qualified Universum as U

import Data.Version (showVersion)

import Lorentz hiding (View)
import Lorentz.Contracts.Spec.TZIP16Interface
import qualified Lorentz.Contracts.Spec.FA2Interface as FA2
import Morley.Metadata

import Ligo.BaseDAO.Types
import qualified Paths_baseDAO_ligo_meta as Paths

-- | Piece of metadata defined by user.
data MetadataConfig = MetadataConfig
  { mcFrozenTokenMetadata :: FA2.TokenMetadata
  , mcUnfrozenTokenMetadata :: FA2.TokenMetadata
  }

-- | All the information for instantiating metadata.
--
-- This includes pieces defined by user (if any) like some constants for
-- off-chain views, as well as abstract storage accessors of the contract.
data MetadataSettings = MetadataSettings
  { msConfig :: MetadataConfig

    -- Haskell-world accessors
  , mcOperatorsL :: U.Lens' Storage Operators
  }

-- | Default values for config.
defaultMetadataConfig :: MetadataConfig
defaultMetadataConfig =
  MetadataConfig
    { mcFrozenTokenMetadata =
        FA2.mkTokenMetadata "frozen_token" "Frozen Token" "8"
    , mcUnfrozenTokenMetadata =
        FA2.mkTokenMetadata "unfrozen_token" "Unfrozen Token" "8"
    }


-- | Construct MetadataSetting for the contract.
mkMetadataSettings :: MetadataConfig -> MetadataSettings
mkMetadataSettings msConfig = MetadataSettings
  { msConfig
  , mcOperatorsL = sOperatorsLens
  }

-- | Parts of metadata that can be filled just knowing the contract,
-- without user's input.
knownBaseDAOMetadata :: MetadataSettings -> Metadata (ToT Storage)
knownBaseDAOMetadata settings = mconcat
  [ version . fromString $ showVersion Paths.version
  , license $ License "MIT" Nothing
  , authors [Author "Serokell", Author "Tocqueville Group"]
  , homepage "https://github.com/tqtezos/baseDAO"
  , interfaces [tzip 12, tzip 17]
  , views (baseDAOViews settings)
  ]

------------------------------------------------------------------------
-- Off-chain views
------------------------------------------------------------------------

baseDAOViews :: MetadataSettings -> [View $ ToT Storage]
baseDAOViews = U.sequence
  [ getBalanceView
  , allTokensView
  , isOperatorView
  , tokenMetadataView
  , getTotalSupplyView

  , permitsCounterView
  ]

type DaoView = MetadataSettings -> View (ToT Storage)

-- FA2
------------------------------------------------------------------------

getBalanceView :: DaoView
getBalanceView MetadataSettings{} = View
  { vName = "get_balance"
  , vDescription = Just
      "Get balance of an address according to TZIP-12."
  , vPure = Just True
  , vImplementations =
      [ VIMichelsonStorageView $
          mkMichelsonStorageView @Storage Nothing [] $
            unsafeCompileViewCode $ WithParam @FA2.BalanceRequestItem $ do
              getField #briOwner; dip (toField #briTokenId); pair
              stGet #sLedger
              fromOption 0
      ]
  }

allTokensView :: DaoView
allTokensView MetadataSettings{} = View
  { vName = "all_tokens"
  , vDescription = Just
      "Get all supported tokens according to TZIP-12."
  , vPure = Just True
  , vImplementations =
      [ VIMichelsonStorageView $
          mkMichelsonStorageView @Storage Nothing [] $
            unsafeCompileViewCode $ WithoutParam $ do
              stGetField #sUnfrozenTokenId
              dip $ do stToField #sFrozenTokenId; dip nil; cons
              cons
      ]
  }

isOperatorView :: DaoView
isOperatorView MetadataSettings{} = View
  { vName = "is_operator"
  , vDescription = Just
      "Checks whether given address is allowed to transfer given tokens \
      \that belong to given owner - according to TZIP-12."
  , vPure = Just True
  , vImplementations =
      [ VIMichelsonStorageView $
          mkMichelsonStorageView @Storage Nothing [] $
            unsafeCompileViewCode $ WithParam @FA2.OperatorParam $ do
              dip dup
              convertOperatorParam
              pair
              stMem #sOperators
      ]
  }

tokenMetadataView :: DaoView
tokenMetadataView MetadataSettings{ msConfig = MetadataConfig{..} } = View
  { vName = "token_metadata"
  , vDescription = Just
      "Returns metadata for given token according to TZIP-12."
  , vPure = Just True
  , vImplementations =
      [ VIMichelsonStorageView $
          mkMichelsonStorageView @Storage Nothing [] $
            unsafeCompileViewCode $ WithParam @FA2.TokenId $ do
              dip $ do
                dup
                dip emptyMap
                stToField #sFrozenTokenId
                push (Just mcFrozenTokenMetadata)
                swap
                update
                swap
                stToField #sUnfrozenTokenId
                push (Just mcUnfrozenTokenMetadata)
                swap
                update
              dup
              dip $ do
                get
                ifSome nop $ failCustom_ #fA2_TOKEN_UNDEFINED
              pair
      ]
  }

getTotalSupplyView :: DaoView
getTotalSupplyView MetadataSettings{ msConfig = MetadataConfig{} } = View
  { vName = "get_total_supply"
  , vDescription = Just
      "Return the total number of tokens for the given token-id if known or fail if not."
  , vPure = Just True
  , vImplementations =
      [ VIMichelsonStorageView $
          mkMichelsonStorageView @Storage Nothing [] $
            unsafeCompileViewCode $ WithParam @FA2.TokenId $ do
              stGet #sTotalSupply
              ifSome nop $ failCustom_ #fA2_TOKEN_UNDEFINED
      ]
  }

-- BaseDAO-specific
------------------------------------------------------------------------

permitsCounterView :: DaoView
permitsCounterView MetadataSettings{} = View
  { vName = "GetCounter"
  , vDescription = Just
      "Returns the next counter value with which a permit should be created."
  , vPure = Just True
  , vImplementations =
      [ VIMichelsonStorageView $
          mkSimpleMichelsonStorageView @Storage $
            unsafeCompileViewCode $ WithoutParam $
              stToField #sPermitsCounter
      ]
  }

-- TODO reconsider this
convertOperatorParam
  :: forall store s.
     ( StoreHasField store "sUnfrozenTokenId" FA2.TokenId
     , StoreHasField store "sFrozenTokenId" FA2.TokenId
     )
  => FA2.OperatorParam : store : s
  :-> ("owner" :! Address) : ("operator" :! Address) : s
convertOperatorParam = do
  getField #opTokenId
  dip do
    getField #opOperator; toNamed #operator
    dip $ do toField #opOwner; toNamed #owner
    dig @2
  -- validateOperatorToken
  dip (stGetField #sUnfrozenTokenId)
  dup
  dip swap
  if IsEq
  then dropN @2 @(FA2.TokenId : store : _)
  else do
    dip (stToField #sFrozenTokenId)
    if IsEq
    then failUsing [mt|OPERATION_PROHIBITED|]
    else failCustom_ #fA2_TOKEN_UNDEFINED
  swap
