// SPDX-FileCopyrightText: 2020 TQ Tezos
// SPDX-License-Identifier: LicenseRef-MIT-TQ

// Corresponds to Types.hs module

// -- FA2 types -- //

#if !TYPES_H
#define TYPES_H

type token_id = nat
type token_metadata =
  [@layout:comb]
  { token_id : token_id
  ; symbol : string
  ; name : string
  ; decimals : nat
  ; extras : (string, string) map
  }

type operator =
  [@layout:comb]
  { owner : address
  ; operator : address
  }
type operators = (operator, unit) big_map

type ledger_key = address * token_id
type ledger_value = nat
type ledger = (ledger_key, ledger_value) big_map

type transfer_destination =
  [@layout:comb]
  { to_ : address
  ; token_id : token_id
  ; amount : nat
  }
type transfer_item =
  [@layout:comb]
  { from_ : address
  ; txs : transfer_destination list
  }
type transfer_params = transfer_item list

type balance_request_item =
  [@layout:comb]
  { owner : address
  ; token_id : token_id
  }
type balance_response_item =
  [@layout:comb]
  { request : balance_request_item
  ; balance : nat
  }
type balance_request_params =
  [@layout:comb]
  { requests : balance_request_item list
  ; callback : balance_response_item list contract
  }

type token_metadata_registry_param = address contract

type operator_param =
  [@layout:comb]
  { owner : address
  ; operator : address
  ; token_id : token_id
  }
type update_operator =
  [@layout:comb]
  | Add_operator of operator_param
  | Remove_operator of operator_param
type update_operators_param = update_operator list

type fa2_parameter =
    Transfer of transfer_params
  | Balance_of of balance_request_params
  | Token_metadata_registry of token_metadata_registry_param
  | Update_operators of update_operators_param

// -- DAO base types -- //

type nonce = nat

type migration_status =
  [@layout:comb]
  | Not_in_migration
  | MigratingTo of address
  | MigratedTo of address

type proposal_key = bytes
type proposal_metadata = (string, bytes) map
type proposal =
  { upvotes : nat
  ; downvotes : nat
  ; start_date : timestamp
  ; metadata : proposal_metadata
  ; proposer : address
  ; proposer_frozen_token : nat
  ; voters : (address * nat) list
  }

type vote_type = bool

type voting_period = nat
type quorum_threshold = nat

type permit =
  { key : key
  ; signature : signature
  }

type contract_extra = (string, bytes) map

// -- Storage -- //

type storage =
  { ledger : ledger
  ; operators : operators
  ; token_address : address
  ; admin : address
  ; pending_owner : address
  ; metadata : (string, bytes) big_map
  ; migration_status : migration_status
  ; voting_period : voting_period
  ; quorum_threshold : quorum_threshold
  ; extra : contract_extra
  ; proposals : (proposal_key, proposal) big_map
  ; proposal_key_list_sort_by_date : (timestamp * proposal_key) set
  ; permits_counter : nonce
  }

// -- Parameter -- //

type transfer_ownership_param = address

type migrate_param = address

type voting_period = nat
type quorum_threshold = nat

type custom_ep_param = (string * bytes)

type propose_params =
  { frozen_token : nat
  ; proposal_metadata : proposal_metadata
  }

type vote_param =
  [@layout:comb]
  { proposal_key : proposal_key
  ; vote_type : vote_type
  ; vote_amount : nat
  }
type vote_param_permited =
  { argument : vote_param
  ; permit : permit option
  }

type burn_param =
  [@layout:comb]
  { from_ : address
  ; token_id : token_id
  ; amount : nat
  }
type mint_param =
  [@layout:comb]
  { to_ : address
  ; token_id : token_id
  ; amount : nat
  }

type transfer_contract_tokens_param =
  { contract_address : address
  ; params : transfer_params
  }

type vote_permit_counter_param =
  [@layout:comb]
  { param : unit
  ; callback : nat contract
  }

type parameter =
    Call_FA2 of fa2_parameter
  | CallCustom of custom_ep_param
  | Drop_proposal of proposal_key
  | Transfer_ownership of transfer_ownership_param
  | Accept_ownership of unit
  | Migrate of migrate_param
  | Confirm_migration of unit
  | Propose of propose_params
  | Vote of vote_param_permited list
  | Set_voting_period of voting_period
  | Set_quorum_threshold of quorum_threshold
  | Flush of nat
  | Burn of burn_param
  | Mint of mint_param
  | Transfer_contract_tokens of transfer_contract_tokens_param
  | GetVotePermitCounter of vote_permit_counter_param

// -- Config -- //

type custom_entrypoints = (string, bytes) map

type decision_lambda_input =
  { proposal : proposal
  ; storage : storage
  }

type config =
  { unfrozen_token_metadata : token_metadata
  ; frozen_token_metadata : token_metadata
  ; proposal_check : propose_params * storage -> bool
  ; rejected_proposal_return_value : proposal * storage -> nat
  ; decision_lambda : proposal * storage -> operation list * storage

  ; max_proposals : nat
  ; max_votes : nat
  ; max_quorum_threshold : nat
  ; min_quorum_threshold : nat
  ; max_voting_period : nat
  ; min_voting_period : nat

  ; custom_entrypoints : custom_entrypoints
  }

type full_storage = storage * config

// -- Misc -- //

type return = operation list * storage

type return_with_full_storage = operation list * full_storage

let nil_op = ([] : operation list)

// Remove this when everything is covered
[@inline]
let not_implemented (func : string) = (failwith(func ^ " is not implemented"): return)

#endif  // TYPES_H included
