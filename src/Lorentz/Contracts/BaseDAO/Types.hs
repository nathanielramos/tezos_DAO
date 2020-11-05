-- SPDX-FileCopyrightText: 2020 TQ Tezos
-- SPDX-License-Identifier: LicenseRef-MIT-TQ
{-# OPTIONS_GHC -Wno-orphans #-}

module Lorentz.Contracts.BaseDAO.Types
  ( Config(..)
  , defaultConfig

  , Operators
  , Ledger
  , LedgerValue

  , Parameter (..)
  , ProposeParams(..)
  , ProposalKey
  , Proposal (..)
  , VotingPeriod
  , VoteParam (..)
  , VoteType
  , QuorumThreshold

  , Storage (..)
  , StorageC
  , TransferOwnershipParam
  , MigrateParam
  , MigrationStatus

  , emptyStorage
  , mkStorage

  , unfrozenTokenId
  , frozenTokenId
  ) where

import Universum hiding ((>>), drop)

import qualified Data.Map.Internal as Map
import Lorentz
import qualified Lorentz.Contracts.Spec.FA2Interface as FA2
import Michelson.Runtime.GState (genesisAddress)
import qualified Data.Kind as Kind
import Util.Markdown

------------------------------------------------------------------------
-- Configuration
------------------------------------------------------------------------

data Config proposalMetadata = Config
  { cDaoName :: Text
  , cDaoDescription :: Markdown
  , cUnfrozenTokenMetadata :: FA2.TokenMetadata
  , cFrozenTokenMetadata :: FA2.TokenMetadata

  , cProposalCheck :: forall s
      . (ProposeParams proposalMetadata) : s
    :-> Bool : s
  -- ^ A lambda used to verify whether a proposal can be submitted.
  -- It checks 2 things: the proposal itself and the amount of tokens frozen upon submission.
  -- It allows the DAO to reject a proposal by arbitrary logic and captures bond requirements

  , cRejectedProposalReturnValue :: forall s
      . (Proposal proposalMetadata) : s
    :-> ("slash_amount" :! Natural) : s
  -- ^ When a proposal is rejected, the value that voters get back can be slashed.
  -- This lambda specifies how many tokens will be received.
  -- For example, if Alice freezes 100 tokens to vote and this lambda divides the value by 2,
  -- only 50 tokens will be unfrozen and other 50 tokens will be burnt.

  , cDecisionLambda :: forall s store. StorageC store proposalMetadata =>
      (Proposal proposalMetadata) : store : s
    :-> (List Operation, store) : s
  -- ^ The decision lambda is executed based on a successful proposal.


  -- Bounded Values
  , cMaxProposals :: Natural
  , cMaxVotes :: Natural -- including both upvotes and downvotes
  , cMaxQuorumThreshold :: Natural
    -- ^ Should not be bigger than 'cMaxVotes' or else if the admin set the
    -- quorum_threshold to max, the threshold could never be met.
  , cMinQuorumThreshold :: Natural
  , cMaxVotingPeriod :: Natural -- Maximum of seconds allow to be set
  , cMinVotingPeriod :: Natural
  }

defaultConfig :: Config pm
defaultConfig = Config
  { cDaoName = "BaseDAO"
  , cDaoDescription = [md|"BaseDAO description"|]
  , cUnfrozenTokenMetadata = FA2.TokenMetadata
      { FA2.tmTokenId = unfrozenTokenId
      , FA2.tmSymbol = [mt|unfrozen_token|]
      , FA2.tmName = [mt|Unfrozen Token|]
      , FA2.tmDecimals = 8
      , FA2.tmExtras = mempty
      }
  , cFrozenTokenMetadata = FA2.TokenMetadata
      { FA2.tmTokenId = frozenTokenId
      , FA2.tmSymbol = [mt|frozen_token|]
      , FA2.tmName = [mt|Frozen Token|]
      , FA2.tmDecimals = 8
      , FA2.tmExtras = mempty
      }
  , cProposalCheck = do
      drop; push True
  , cRejectedProposalReturnValue = do
      drop; push (0 :: Natural); toNamed #slash_amount
  , cDecisionLambda = do
      drop; nil; pair

  , cMaxVotingPeriod = 60 * 60 * 24 * 30
  , cMinVotingPeriod = 1 -- value between 1 second - 1 month

  , cMaxQuorumThreshold = 1000
  , cMinQuorumThreshold = 1

  , cMaxVotes = 1000
  , cMaxProposals = 500
  }
------------------------------------------------------------------------
-- Operators
------------------------------------------------------------------------

type Operators = BigMap (Address, Address) ()

------------------------------------------------------------------------
-- Ledger
------------------------------------------------------------------------

type Ledger = BigMap LedgerKey LedgerValue

type LedgerKey = (Address, FA2.TokenId)

type LedgerValue = Natural

------------------------------------------------------------------------
-- Storage/Parameter
------------------------------------------------------------------------

-- | Migration status of the contract
data MigrationStatus
  = NotInMigration
  | MigratingTo Address
  | MigratedTo Address
  deriving stock (Generic, Show)
  deriving anyclass (IsoValue, HasAnnotation)

instance TypeHasDoc MigrationStatus where
  typeDocMdDescription =
    "Migration status of the contract"

-- | Storage of the FA2 contract
data Storage (proposalMetadata :: Kind.Type) = Storage
  { sLedger       :: Ledger
  , sOperators    :: Operators
  , sTokenAddress :: Address
  , sAdmin        :: Address
  , sPendingOwner :: Maybe Address
  , sMigrationStatus :: MigrationStatus

  , sVotingPeriod :: VotingPeriod
  , sQuorumThreshold :: QuorumThreshold

  , sProposals :: BigMap ProposalKey (Proposal proposalMetadata)
  , sProposalKeyListSortByDate :: [ProposalKey] -- Newest first
  }
  deriving stock (Generic, Show)
  deriving anyclass (HasAnnotation)

deriving anyclass instance (WellTypedIsoValue proposalMetadata) => IsoValue (Storage proposalMetadata)

instance HasFieldOfType (Storage pm) name field =>
         StoreHasField (Storage pm) name field where
  storeFieldOps = storeFieldOpsADT

instance IsoValue pm =>
    StoreHasSubmap (Storage pm) "sLedger" LedgerKey LedgerValue where
  storeSubmapOps = storeSubmapOpsDeeper #sLedger

instance IsoValue pm =>
    StoreHasSubmap (Storage pm) "sOperators" (Address, Address) () where
  storeSubmapOps = storeSubmapOpsDeeper #sOperators

instance IsoValue pm =>
    StoreHasSubmap (Storage pm) "sProposals" ProposalKey (Proposal pm) where
  storeSubmapOps = storeSubmapOpsDeeper #sProposals

type StorageC store pm =
  ( StorageContains store
    [ "sLedger" := LedgerKey ~> LedgerValue
    , "sOperators" := (Address, Address) ~> ()
    , "sTokenAddress" := Address
    , "sAdmin" := Address
    , "sPendingOwner" := Maybe Address
    , "sLedger" := Ledger
    , "sMigrationStatus" := MigrationStatus

    , "sVotingPeriod" := VotingPeriod
    , "sQuorumThreshold" := QuorumThreshold

    , "sProposals" := ProposalKey ~> Proposal pm
    , "sProposalKeyListSortByDate" := [ProposalKey]
    ]
  )

-- | Parameter of the BaseDAO contract
data Parameter proposalMetadata
  = Call_FA2 FA2.Parameter
  | Transfer_ownership TransferOwnershipParam
  | Accept_ownership ()
  | Migrate MigrateParam
  | Confirm_migration ()
  | Propose (ProposeParams proposalMetadata)
  | Proposal_metadata (View ProposalKey (Proposal proposalMetadata))
  | Vote [VoteParam]
  -- Admin
  | Set_voting_period VotingPeriod
  | Set_quorum_threshold QuorumThreshold
  | Flush ()
  deriving stock (Generic, Show)

instance (HasAnnotation pm, NiceParameter pm) => ParameterHasEntrypoints (Parameter pm) where
  type ParameterEntrypointsDerivation (Parameter pm) = EpdDelegate

deriving anyclass instance (WellTypedIsoValue pm) => IsoValue (Parameter pm)

type TransferOwnershipParam = ("newOwner" :! Address)
type MigrateParam = ("newAddress" :! Address)

-- | Voting period in seconds
type VotingPeriod = Natural

-- | QuorumThreshold that a proposal need to meet
-- A proposal will be rejected if the quorum_threshold is not met,
-- regardless of upvotes > downvotes
-- A proposal will be accepted only if the
-- (quorum_threshold >= upvote + downvote) && (upvote > downvote)
type QuorumThreshold = Natural

emptyStorage :: Storage pm
emptyStorage = Storage
  { sLedger =  BigMap $ Map.empty
  , sOperators = BigMap $ Map.empty
  , sTokenAddress = genesisAddress
  , sPendingOwner = Nothing
  , sAdmin = genesisAddress
  , sMigrationStatus = NotInMigration
  , sVotingPeriod = 60 * 60 * 24 * 7 -- 7 days
  , sQuorumThreshold = 4
    -- ^ any proposals that have less that 4 votes will be rejected
    -- regardless of upvotes

  , sProposals = BigMap $ Map.empty
  , sProposalKeyListSortByDate = []
  }

mkStorage
  :: Address
  -> Map (Address, FA2.TokenId) Natural
  -> Operators
  -> Storage pm
mkStorage admin balances operators = Storage
  { sLedger = BigMap balances
  , sOperators = operators
  , sTokenAddress = genesisAddress
  , sPendingOwner = Nothing
  , sAdmin = admin
  , sMigrationStatus = NotInMigration
  , sVotingPeriod = 60 * 60 * 24 * 7 -- days
  , sQuorumThreshold = 4

  , sProposals = BigMap $ Map.empty
  , sProposalKeyListSortByDate = []
  }

------------------------------------------------------------------------
-- Proposal
------------------------------------------------------------------------

type ProposalKey = ByteString

-- | Proposal type which will be stored in 'Storage' `sProposals`
-- `pVoters` is needed due to we need to keep track of voters to be able to
-- unfreeze their tokens.
data Proposal proposalMetadata = Proposal
  { pUpvotes :: Natural
  , pDownvotes :: Natural
  , pStartDate :: Timestamp

  , pMetadata :: proposalMetadata

  , pProposer :: Address
  , pProposerFrozenToken :: Natural

  , pVoters :: [(Address, Natural)]
  }
  deriving stock (Generic, Show)
  deriving anyclass (IsoValue, HasAnnotation)

instance (TypeHasDoc pm, IsoValue pm) => TypeHasDoc (Proposal pm) where
  typeDocMdDescription =
    "Contract's storage holding a big_map with all balances and the operators."
  typeDocMdReference = poly1TypeDocMdReference
  typeDocHaskellRep = concreteTypeDocHaskellRep @(Proposal ())
  typeDocMichelsonRep = concreteTypeDocMichelsonRep @(Proposal ())

------------------------------------------------------------------------
-- Propose
------------------------------------------------------------------------

data ProposeParams proposalMetadata = ProposeParams
  { ppFrozenToken :: Natural
  --  ^ Determines how many sender's tokens will be frozen to get
  -- the proposal accepted
  , ppProposalMetadata :: proposalMetadata
  }
  deriving stock (Generic, Show)
  deriving anyclass (IsoValue, HasAnnotation)

instance (TypeHasDoc pm, IsoValue pm) => TypeHasDoc (ProposeParams pm) where
  typeDocMdDescription =
     "Describes the how many proposer's frozen tokens will be frozen and the proposal metadata"
  typeDocMdReference = poly1TypeDocMdReference
  typeDocHaskellRep = concreteTypeDocHaskellRep @(ProposeParams ())
  typeDocMichelsonRep = concreteTypeDocMichelsonRep @(ProposeParams ())

------------------------------------------------------------------------
-- Propose
------------------------------------------------------------------------
type VoteType = Bool

data VoteParam = VoteParam
  { vProposalKey :: ProposalKey
  , vVoteType :: VoteType
  , vVoteAmount :: Natural
  }
  deriving stock (Generic, Show)
  deriving anyclass (IsoValue, HasAnnotation)

instance TypeHasDoc VoteParam where
  typeDocMdDescription = "Describes target proposal id, vote type and vote amount"

------------------------------------------------------------------------
-- Tokens
------------------------------------------------------------------------

unfrozenTokenId :: FA2.TokenId
unfrozenTokenId = 0

frozenTokenId :: FA2.TokenId
frozenTokenId = 1

------------------------------------------------------------------------
-- Error
------------------------------------------------------------------------

type instance ErrorArg "nOT_OWNER" = ()

instance CustomErrorHasDoc "nOT_OWNER" where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "The sender of transaction is not owner"

type instance ErrorArg "fROZEN_TOKEN_NOT_TRANSFERABLE" = ()

instance CustomErrorHasDoc "fROZEN_TOKEN_NOT_TRANSFERABLE" where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "The sender tries to transfer frozen token"

type instance ErrorArg "nO_PENDING_ADMINISTRATOR_SET" = ()

instance CustomErrorHasDoc "nO_PENDING_ADMINISTRATOR_SET" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Received an `accept_ownership` call when no pending owner was set"

type instance ErrorArg "nOT_PENDING_ADMINISTRATOR" = ()

instance CustomErrorHasDoc "nOT_PENDING_ADMINISTRATOR" where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "Received an `accept_ownership` from an address other than what is in the pending owner field"

type instance ErrorArg "nOT_ADMINISTRATOR" = ()

instance CustomErrorHasDoc "nOT_ADMINISTRATOR" where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "Received an operation that require administrative privileges\
    \ from an address that is not the current administrator"

type instance ErrorArg "mIGRATED" = Address

instance CustomErrorHasDoc "mIGRATED" where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "Recieved a call on a migrated contract"

type instance ErrorArg "nOT_MIGRATING" = ()

instance CustomErrorHasDoc "nOT_MIGRATING" where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "Recieved a confirm_migration call on a contract that is not in migration"

type instance ErrorArg "nOT_MIGRATION_TARGET" = ()

instance CustomErrorHasDoc "nOT_MIGRATION_TARGET" where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "Recieved a confirm_migration call on a contract from an address other than the new version"

type instance ErrorArg "fORBIDDEN_XTZ" = ()

instance CustomErrorHasDoc "fORBIDDEN_XTZ" where
  customErrClass = ErrClassActionException
  customErrDocMdCause =
    "Received some XTZ as part of a contract call, which is forbidden"

type instance ErrorArg "fAIL_PROPOSAL_CHECK" = ()

instance CustomErrorHasDoc "fAIL_PROPOSAL_CHECK" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to propose a proposal that does not pass `proposalCheck`"

type instance ErrorArg "pROPOSAL_INSUFFICIENT_BALANCE" = ()

instance CustomErrorHasDoc "pROPOSAL_INSUFFICIENT_BALANCE" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to propose a proposal without having enough unfrozen token"

type instance ErrorArg "vOTING_INSUFFICIENT_BALANCE" = ()

instance CustomErrorHasDoc "vOTING_INSUFFICIENT_BALANCE" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to vote on a proposal without having enough unfrozen token"

type instance ErrorArg "pROPOSAL_NOT_EXIST" = ()

instance CustomErrorHasDoc "pROPOSAL_NOT_EXIST" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to vote on a proposal that does not exist"

type instance ErrorArg "vOTING_PERIOD_OVER" = ()

instance CustomErrorHasDoc "vOTING_PERIOD_OVER" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to vote on a proposal that is already ended"

------------------------------------------------
-- Error causes by bounded value
------------------------------------------------

type instance ErrorArg "oUT_OF_BOUND_VOTING_PERIOD" = ()

instance CustomErrorHasDoc "oUT_OF_BOUND_VOTING_PERIOD" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to set voting period that is out of bound."

type instance ErrorArg "oUT_OF_BOUND_QUORUM_THRESHOLD" = ()

instance CustomErrorHasDoc "oUT_OF_BOUND_QUORUM_THRESHOLD" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to set quorum threshold that is out of bound"

type instance ErrorArg "mAX_PROPOSALS_REACHED" = ()

instance CustomErrorHasDoc "mAX_PROPOSALS_REACHED" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to propose a proposal when proposals max amount is already reached"

type instance ErrorArg "mAX_VOTES_REACHED" = ()

instance CustomErrorHasDoc "mAX_VOTES_REACHED" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to vote on a proposal when the votes max amount of that proposal is already reached"

type instance ErrorArg "pROPOSER_NOT_EXIST_IN_LEDGER" = ()

instance CustomErrorHasDoc "pROPOSER_NOT_EXIST_IN_LEDGER" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Expect a proposer address to exist in Ledger but it is not found (Impossible Case)"

type instance ErrorArg "pROPOSAL_NOT_UNIQUE" = ()

instance CustomErrorHasDoc "pROPOSAL_NOT_UNIQUE" where
  customErrClass = ErrClassActionException
  customErrDocMdCause = "Trying to propose a proposal that is already existed in the Storage."
