// SPDX-FileCopyrightText: 2021 Tezos Commons
// SPDX-License-Identifier: LicenseRef-MIT-TC

#include "../types.mligo"
#include "../error_codes.mligo"


let add_frozen_fh (amt, fh : nat * address_freeze_history): address_freeze_history =
  { fh with current_unstaked = fh.current_unstaked + amt }

let sub_frozen_fh (amt, fh : nat * address_freeze_history): address_freeze_history =
  match is_nat(fh.past_unstaked - amt) with
  | Some new_amt -> { fh with past_unstaked = new_amt }
  | None ->
      (failwith not_enough_frozen_tokens : address_freeze_history)

let stake_frozen_fh (amt, fh : nat * address_freeze_history): address_freeze_history =
  let fh = sub_frozen_fh(amt, fh) in
  { fh with staked = fh.staked + amt }

let unstake_frozen_fh (amt_to_unstake, amt_to_burn, fh : nat * nat * address_freeze_history): address_freeze_history =
  match is_nat(fh.staked - (amt_to_unstake + amt_to_burn)) with
  | Some new_staked_amt ->
      { fh with staked = new_staked_amt; past_unstaked = fh.past_unstaked + amt_to_unstake }
  | None ->
      (failwith bad_state : address_freeze_history)

// Update a possibly outdated freeze_history for the current stage
let update_fh (current_stage, freeze_history : nat * address_freeze_history): address_freeze_history =
  if freeze_history.current_stage_num < current_stage
  then
    { current_stage_num = current_stage
    ; staked = freeze_history.staked
    ; current_unstaked = 0n
    ; past_unstaked = freeze_history.current_unstaked + freeze_history.past_unstaked
    }
  else freeze_history
