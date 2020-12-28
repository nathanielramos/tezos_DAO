-- SPDX-FileCopyrightText: 2020 TQ Tezos
-- SPDX-License-Identifier: LicenseRef-MIT-TQ

-- | RegistryDAO Types
module Lorentz.Contracts.RegistryDAO.Types
  ( RegistryDaoContractExtra (..)
  , RegistryEntry (..)
  , RegistryUpdate (..)
  , RegistryDaoProposalMetadata (..)
  , NormalProposal (..)
  , ConfigProposal (..)
  , IsoRegistryDaoProposalMetadata
  , AgoraPostId (..)
  ) where

import Lorentz

import qualified Lorentz.Contracts.BaseDAO.Types as DAO


data RegistryDaoContractExtra k v = RegistryDaoContractExtra
  { ceRegistry :: BigMap k (RegistryEntry k v)
  , ceFrozenScaleValue :: Natural
  , ceFrozenExtraValue :: Natural
  , ceSlashScaleValue :: Natural
  , ceSlashDivisionValue :: Natural
  , ceMaxProposalSize :: Natural
  }
  deriving stock (Generic)

instance (NiceComparable k, Ord k, IsoValue k, IsoValue v)
  => (IsoValue (RegistryDaoContractExtra k v))

instance (HasAnnotation k, HasAnnotation v)
  => HasAnnotation (RegistryDaoContractExtra k v) where
    annOptions = DAO.baseDaoAnnOptions

instance (Ord k, NiceComparable k, IsoValue v, TypeHasDoc k, TypeHasDoc v)
  => TypeHasDoc (RegistryDaoContractExtra k v) where
    typeDocMdDescription =
      "Describe the contract extra fields of a registry DAO. It contain a registry as a `BigMap` of a key \
      \`k` and a value of `RegistryEntry v`. It also contains various configurable values that can \
      \ be updated via `ConfigProposal`"
    typeDocMdReference = poly2TypeDocMdReference
    typeDocHaskellRep = concreteTypeDocHaskellRep @(RegistryDaoContractExtra ByteString ByteString)
    typeDocMichelsonRep = concreteTypeDocMichelsonRep @(RegistryDaoContractExtra ByteString ByteString)

instance Default (RegistryDaoContractExtra k v) where
  def = RegistryDaoContractExtra
    { ceRegistry = def
    , ceFrozenScaleValue = 1
    , ceFrozenExtraValue = 0
    , ceSlashScaleValue = 1
    , ceSlashDivisionValue = 1
    , ceMaxProposalSize = 100
    }

instance IsoRegistryDaoProposalMetadata k v =>
    StoreHasSubmap (RegistryDaoContractExtra k v) "ceRegistry" k (RegistryEntry k v) where
  storeSubmapOps = storeSubmapOpsDeeper #ceRegistry


data RegistryEntry k v = RegistryEntry
  { reValue :: Maybe v
   -- optional statistics on given proposal
  , reAffectedProposalKey :: DAO.ProposalKey (RegistryDaoProposalMetadata k v)
  , reLastUpdated :: Timestamp
  } deriving stock (Eq, Generic)
  deriving anyclass (IsoValue)

instance (HasAnnotation k, HasAnnotation v)
  => HasAnnotation (RegistryEntry k v) where
    annOptions = DAO.baseDaoAnnOptions

instance (NiceComparable k, Ord k, IsoValue v, TypeHasDoc k, TypeHasDoc v)
  => TypeHasDoc (RegistryEntry k v) where
    typeDocMdDescription =
      "Describe the value in registry map. It represents the actual item of the registry as `Maybe v`. \
      \`None` represents the deletion of item and `Some v` represents the existence of an item.\
      \It also contains the last proposal's agora post id that affects this item and its last updated time."
    typeDocMdReference = poly2TypeDocMdReference
    typeDocHaskellRep = concreteTypeDocHaskellRep @(RegistryEntry ByteString ByteString)
    typeDocMichelsonRep = concreteTypeDocMichelsonRep @(RegistryEntry ByteString ByteString)


data RegistryDaoProposalMetadata k v
  = NormalProposalType (NormalProposal k v)
  | ConfigProposalType ConfigProposal
  deriving stock (Generic)

type IsoRegistryDaoProposalMetadata k v = (NiceComparable k, Ord k, IsoValue k, KnownValue v)

instance IsoRegistryDaoProposalMetadata k v
  => (IsoValue (RegistryDaoProposalMetadata k v))

instance (HasAnnotation k, HasAnnotation v)
  => HasAnnotation (RegistryDaoProposalMetadata k v) where
    annOptions = DAO.baseDaoAnnOptions

instance (TypeHasDoc k, TypeHasDoc v)
  => TypeHasDoc (RegistryDaoProposalMetadata k v) where
    typeDocMdDescription =
      "Describe the metadata of a proposal in Registry DAO. In Registry DAO, there are 2 types of \
      \proposals: a registry proposal, represented as `NormalProposal k v` and a configuration proposal \
      \represented as `ConfigProposal`."
    typeDocMdReference = poly2TypeDocMdReference
    typeDocHaskellRep = concreteTypeDocHaskellRep @(RegistryDaoProposalMetadata ByteString ByteString)
    typeDocMichelsonRep = concreteTypeDocMichelsonRep @(RegistryDaoProposalMetadata ByteString ByteString)


-- | A registry proposal. It will update registry list in contract storage when got accepted.
data NormalProposal k v = NormalProposal
  { npAgoraPostId :: AgoraPostId
  , npDiff :: [RegistryUpdate k v]
  }
  deriving stock (Generic)

instance IsoRegistryDaoProposalMetadata k v
  => (IsoValue (NormalProposal k v))

instance (HasAnnotation k, HasAnnotation v)
  => HasAnnotation (NormalProposal k v) where
    annOptions = DAO.baseDaoAnnOptions

instance (TypeHasDoc k, TypeHasDoc v)
  => TypeHasDoc (NormalProposal k v) where
    typeDocMdDescription =
      "Describe a proposal for add/update/delete an item in the registry."
    typeDocMdReference = poly2TypeDocMdReference
    typeDocDependencies p = genericTypeDocDependencies p <> [dTypeDep @ByteString]
    typeDocHaskellRep = concreteTypeDocHaskellRep @(NormalProposal ByteString ByteString)
    typeDocMichelsonRep = concreteTypeDocMichelsonRep @(NormalProposal ByteString ByteString)

newtype AgoraPostId = AgoraPostId Natural
  deriving stock (Generic)
  deriving anyclass (IsoValue)

instance HasAnnotation AgoraPostId where
  annOptions = DAO.baseDaoAnnOptions

instance TypeHasDoc AgoraPostId where
  typeDocMdDescription = "Describe an Agora post ID."

-- | Special proposal that allow updating certain scale values in 'contractExtra'
data ConfigProposal = ConfigProposal
  { cpFrozenScaleValue :: Maybe Natural -- a
  , cpFrozenExtraValue :: Maybe Natural -- b
  , cpSlashScaleValue :: Maybe Natural -- c
  , cpSlashDivisionValue :: Maybe Natural -- d
  , cpMaxProposalSize :: Maybe Natural -- s_max
  }
  deriving stock (Generic)
  deriving anyclass (IsoValue)

instance HasAnnotation ConfigProposal where
  annOptions = DAO.baseDaoAnnOptions

instance TypeHasDoc ConfigProposal where
  typeDocMdDescription =
    "Describe a configuration proposal in Registry DAO. It is used to \
    \update the configuration values in contract extra that affect the process of \
    \checking if a proposal is valid or not and how tokens are slash when a proposal \
    \is rejected."


data RegistryUpdate k v = RegistryUpdateItem
  { ruKey :: k
  , ruNewValue :: Maybe v
  } deriving stock (Generic)

instance  (NiceComparable k, Ord k, IsoValue k, IsoValue v)
  => (IsoValue (RegistryUpdate k v))

instance (HasAnnotation k, HasAnnotation v)
  => HasAnnotation (RegistryUpdate k v) where
    annOptions = DAO.baseDaoAnnOptions

instance (TypeHasDoc k, TypeHasDoc v)
  => TypeHasDoc (RegistryUpdate k v) where
    typeDocMdDescription =
      "Describe a proposed change to an items in the registry."
    typeDocMdReference = poly2TypeDocMdReference
    typeDocDependencies p = genericTypeDocDependencies p <> [dTypeDep @ByteString]
    typeDocHaskellRep = concreteTypeDocHaskellRep @(RegistryUpdate ByteString ByteString)
    typeDocMichelsonRep = concreteTypeDocMichelsonRep @(RegistryUpdate ByteString ByteString)
