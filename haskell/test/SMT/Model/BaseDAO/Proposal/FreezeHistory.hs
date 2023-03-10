-- SPDX-FileCopyrightText: 2021 Tezos Commons
-- SPDX-License-Identifier: LicenseRef-MIT-TC

module SMT.Model.BaseDAO.Proposal.FreezeHistory
  ( getCurrentStageNum

  , freezingUpdateFh
  , stakingUpdateFh
  , burnUpdateFh
  ) where

import Universum

import Control.Monad.Except (throwError)
import Data.Map qualified as Map
import GHC.Natural (minusNaturalMaybe)

import Lorentz hiding (cast, div, fromInteger, get, not, or, take)
import Morley.Michelson.Typed.Haskell.Value (BigMap(..))

import Ligo.BaseDAO.Types
import SMT.Model.BaseDAO.Types

getCurrentStageNum :: ModelT cep Natural
getCurrentStageNum = do
  (Period vp) <- getConfig <&> cPeriod
  startLvl <- getStore <&> sStartLevel
  lvl <- get <&> msLevel
  case lvl `minusNaturalMaybe` startLvl of
    Just elapsedLevel -> pure $ elapsedLevel `div` vp
    Nothing -> error "BAD_STATE: Current lvl is smaller than `startLvl`."


-- | Add/substract an amount of tokens from unstaked depending on positive/negative `amt`
-- Postive `amt` will trigger the addition to current unstaked
-- Negative `amt` will trigger the substraction from past unstaked
freezingUpdateFh :: Address -> Integer -> ModelT cep ()
freezingUpdateFh senderAddr amt = do
  if amt < 0 then
    -- `amt` is negative, we substract from past unstaked.
    let unfrozenAmt = fromInteger $ negate amt
    in
      updatedFreezeHistory senderAddr
      >>= modifyPastUnstaked (\pastUnstaked ->
            case pastUnstaked `minusNaturalMaybe` unfrozenAmt of
              Just newStakedAmt -> pure newStakedAmt
              Nothing -> throwError NOT_ENOUGH_FROZEN_TOKENS
            )
      >>= storeFreezeHistory senderAddr
  else
    -- `amt` is positive, we add to current unstaked.
    updatedFreezeHistory senderAddr
      >>= modifyCurrentUnstaked (\unstaked -> pure (unstaked + fromInteger amt))
      >>= storeFreezeHistory senderAddr


-- | Move an amount of tokens from unstake to stake / stake to unstake depending on amt
-- Postive `amt` will trigger moving unstake to stake
-- Negative `amt` will trigger stake to unstake
stakingUpdateFh :: Address -> Integer -> ModelT cep ()
stakingUpdateFh senderAddr amt = do
  if amt == 0 then
    updatedFreezeHistory senderAddr
    >>= storeFreezeHistory senderAddr
  else if amt < 0 then
    -- `amt` is negative, we unstake the tokens.
    let unstakedAmt = fromInteger $ negate amt
    in
      updatedFreezeHistory senderAddr
      >>= modifyStaked (\staked ->
            case staked `minusNaturalMaybe` unstakedAmt of
              Just newStakedAmt -> pure newStakedAmt
              Nothing ->
                error "BAD_STATE: Unstake amount is more than staked amount."
            )
      >>= modifyPastUnstaked (\pastUnstaked -> pure (pastUnstaked + unstakedAmt))
      >>= storeFreezeHistory senderAddr

  else
    -- `amt` is positive, we stake the tokens.
    updatedFreezeHistory senderAddr
    >>= modifyStaked (\staked -> pure (staked + fromInteger amt))
    >>= modifyPastUnstaked (\pastUnstaked ->
          case pastUnstaked `minusNaturalMaybe` fromInteger amt of
            Just newStakedAmt -> pure newStakedAmt
            Nothing -> throwError NOT_ENOUGH_FROZEN_TOKENS
          )
    >>= storeFreezeHistory senderAddr


-- | Delete an amount of token from stake tokens
burnUpdateFh :: Address -> Natural -> ModelT cep ()
burnUpdateFh senderAddr amtToBurn =
  updatedFreezeHistory senderAddr
  >>= modifyStaked (\val ->
        case val `minusNaturalMaybe` amtToBurn of
          Just newStakedAmt -> pure newStakedAmt
          Nothing ->
            error "BAD_STATE: Burn amount is more than staked amount."
        )
  >>= storeFreezeHistory senderAddr


-----------------------------------------------------------------------------------
-- Helper
-----------------------------------------------------------------------------------

modifyCurrentUnstaked
  ::(Natural -> ModelT cep Natural)
  -> AddressFreezeHistory
  -> ModelT cep AddressFreezeHistory
modifyCurrentUnstaked fn fh = do
  newVal <- fn $ fhCurrentUnstaked fh
  return $ fh { fhCurrentUnstaked = newVal }

modifyPastUnstaked
  ::(Natural -> ModelT cep Natural)
  -> AddressFreezeHistory
  -> ModelT cep AddressFreezeHistory
modifyPastUnstaked fn fh = do
  newVal <- fn $ fhPastUnstaked fh
  return $ fh { fhPastUnstaked = newVal }

modifyStaked
  ::(Natural -> ModelT cep Natural)
  -> AddressFreezeHistory
  -> ModelT cep AddressFreezeHistory
modifyStaked fn fh = do
  newVal <- fn $ fhStaked fh
  return $ fh { fhStaked = newVal }

updatedFreezeHistory :: Address -> ModelT cep AddressFreezeHistory
updatedFreezeHistory addr = do
  currentStage <- getCurrentStageNum
  store <- getStore
  pure $ case Map.lookup addr (store & sFreezeHistory & bmMap) of
    Nothing ->
      -- if no freeze history exists, return an "empty" value
      AddressFreezeHistory
        { fhCurrentStageNum = currentStage
        , fhStaked = 0
        , fhCurrentUnstaked = 0
        , fhPastUnstaked = 0
        }
    Just freezeHistory ->
      -- if one does exist, instead updated it (if needed) and return this value
      if (freezeHistory & fhCurrentStageNum) < currentStage then
        AddressFreezeHistory
          { fhCurrentStageNum = currentStage
          , fhStaked = freezeHistory & fhStaked
          , fhCurrentUnstaked = 0
          , fhPastUnstaked = (freezeHistory & fhCurrentUnstaked) + (freezeHistory & fhPastUnstaked)
          }
      else freezeHistory

storeFreezeHistory :: Address -> AddressFreezeHistory -> ModelT cep ()
storeFreezeHistory addr fh = modifyStore $ \s ->
  pure $ s { sFreezeHistory = BigMap Nothing $ Map.insert addr fh (s & sFreezeHistory & bmMap)}
