// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PayMaster} from "./PayMaster.sol";
import {UniswapV3Integration} from "./UniswapV3Integration.sol";
import {Liquidity} from "./Liquidity.sol";
import {Errors} from "../interfaces/Errors.sol";
import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import "../interfaces/IPoolPartyPosition.sol";

/**
 * @title MintPosition Library
 * @notice This library is used to handle the creation of new positions within a Uniswap V3 pool.
 * It ensures that the required tokens are transferred and approved, and manages the minting of the position.
 */
library MintPosition {
    using PositionIdLib for PositionKey;
    using SafeERC20 for IERC20;

    /**
     * @notice Mints a new position in the pool.
     * @param s The storage reference for the pool position.
     * @param _position The pool position.
     * @param _recipient The address to receive the minted position.
     * @param _params The parameters required to mint the position.
     * @return positionId The ID of the minted position.
     * @return _tokenId The token ID of the minted position.
     * @return _liquidity The amount of liquidity added.
     * @return amount0 The amount of currency0 added.
     * @return amount1 The amount of currency1 added.
     */
    function mintPosition(
        Storage storage s,
        IPoolPartyPosition _position,
        address _recipient,
        IPoolPartyPosition.MintPositionParams memory _params
    )
        external
        returns (
            PositionId positionId,
            uint256 _tokenId,
            uint128 _liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        //slither-disable-next-line timestamp
        require(_params.deadline >= block.timestamp, Errors.ExpiredDeadline());
        require(
            _params.amount0Desired > 0 || _params.amount1Desired > 0,
            Errors.CurrencyAmountCannotBeZero(
                _params.amount0Desired,
                _params.amount1Desired
            )
        );

        PayMaster.wrapETHOrTransferToken(
            _position,
            s.i_currency0,
            _params.amount0Desired,
            _recipient
        );

        PayMaster.wrapETHOrTransferToken(
            _position,
            s.i_currency1,
            _params.amount1Desired,
            _recipient
        );

        IERC20(s.i_currency0).forceApprove(
            address(s.i_nonfungiblePositionManager),
            _params.amount0Desired
        );

        IERC20(s.i_currency1).forceApprove(
            address(s.i_nonfungiblePositionManager),
            _params.amount1Desired
        );
        (_tokenId, _liquidity, amount0, amount1) = UniswapV3Integration.mint({
            s: s,
            _recipient: _recipient,
            _tickLower: s.positionKey.tickLower,
            _tickUpper: s.positionKey.tickUpper,
            _amount0Desired: _params.amount0Desired,
            _amount1Desired: _params.amount1Desired,
            _amount0Min: _params.amount0Min,
            _amount1Min: _params.amount1Min,
            _deadline: _params.deadline
        });

        s.tokenId = _tokenId;

        try
            UniswapV3Integration.getAmountsFromLiquidity(_position, _liquidity)
        returns (uint256 _amount0, uint256 _amount1) {
            if (_amount0 > amount0 || _amount1 > amount1) {
                revert Errors.InvalidLiquidityAmounts();
            }
        } catch {
            revert Errors.InvalidLiquidityAmounts();
        }

        if (_params.amount0Desired - amount0 > 0) {
            PayMaster.refundWithUnwrapedWETHOrToken(
                _position,
                s.i_currency0,
                _params.amount0Desired - amount0,
                s.i_operator
            );
        }

        if (_params.amount1Desired - amount1 > 0) {
            PayMaster.refundWithUnwrapedWETHOrToken(
                _position,
                s.i_currency1,
                _params.amount1Desired - amount1,
                s.i_operator
            );
        }

        s.uniswapLiquidityOf[s.i_operator] = _liquidity;
        s.uniswapLiquidity = _liquidity;
        s.liquidity = Liquidity._calcAddLiquidity(0, amount0, amount1);

        s.liquidityOf[s.i_operator] = s.liquidity;
        s.operatorMintLiquidity[s.i_operator] = s.liquidity;

        positionId = s.positionKey.toId();
        s.isOpen[positionId][s.tokenId] = true;

        // slither-disable-next-line reentrancy-events
        emit IPoolPartyPositionEvents.PositionCreated(
            s.i_operator,
            s.tokenId,
            positionId,
            _recipient
        );
    }
}
