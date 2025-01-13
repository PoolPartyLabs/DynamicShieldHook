// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IV3SwapRouter} from "../interfaces/IV3SwapRouter.sol";
import {INonfungiblePositionManager} from "../interfaces/INonfungiblePositionManager.sol";
import {IPoolPartyPosition} from "../interfaces/IPoolPartyPosition.sol";
import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import {LiquidityAmounts} from "./uniswap/LiquidityAmounts.sol";
import {TickMath} from "./uniswap/TickMath.sol";
import {PositionValue} from "./uniswap/PositionValue.sol";
import {PositionKey} from "../types/PositionKey.sol";
import {PositionId, PositionIdLib} from "../types/PositionId.sol";

/**
 * @title UniswapV3Integration Library
 * @notice This library provides functions to interact with Uniswap V3, including minting, increasing, decreasing, and collecting liquidity.
 */
library UniswapV3Integration {
    using PositionIdLib for PositionKey;
    using SafeERC20 for IERC20;

    /**
     * @notice Mints a new position in the Uniswap V3 pool.
     * @param s The storage reference for the pool position.
     * @param _recipient The address to receive the minted position.
     * @param _amount0Min The minimum amount of currency0 to mint.
     * @param _amount1Min The minimum amount of currency1 to mint.
     * @param _amount0Desired The desired amount of currency0 to mint.
     * @param _amount1Desired The desired amount of currency1 to mint.
     * @param _deadline The deadline by which the minting must be completed.
     * @return tokenId The ID of the minted position.
     * @return liquidity The amount of liquidity added.
     * @return amount0 The amount of currency0 added.
     * @return amount1 The amount of currency1 added.
     */
    function mint(
        Storage storage s,
        address _recipient,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Min,
        uint256 _amount1Min,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _deadline
    )
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        address currency0 = s.positionKey.currency0;
        address currency1 = s.positionKey.currency1;
        uint24 fee = s.positionKey.fee;
        //slither-disable-next-line reentrancy-no-eth,locked-ether
        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(
            s.i_nonfungiblePositionManager
        ).mint(
                INonfungiblePositionManager.MintParams({
                    currency0: currency0,
                    currency1: currency1,
                    fee: fee,
                    tickLower: _tickLower,
                    tickUpper: _tickUpper,
                    amount0Desired: _amount0Desired,
                    amount1Desired: _amount1Desired,
                    amount0Min: _amount0Min,
                    amount1Min: _amount1Min,
                    recipient: _recipient,
                    deadline: _deadline
                })
            );
    }

    /**
     * @notice Increases liquidity in an existing Uniswap V3 position.
     * @param s The storage reference for the pool position.
     * @param _amount0Min The minimum amount of currency0 to add.
     * @param _amount1Min The minimum amount of currency1 to add.
     * @param _amount0Desired The desired amount of currency0 to add.
     * @param _amount1Desired The desired amount of currency1 to add.
     * @param _deadline The deadline by which the increase must be completed.
     * @return liquidity The amount of liquidity added.
     * @return amount0 The amount of currency0 added.
     * @return amount1 The amount of currency1 added.
     */
    function increase(
        Storage storage s,
        uint256 _amount0Min,
        uint256 _amount1Min,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _deadline
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        //slither-disable-next-line reentrancy-no-eth,locked-ether
        (liquidity, amount0, amount1) = INonfungiblePositionManager(
            s.i_nonfungiblePositionManager
        ).increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: s.tokenId,
                    amount0Desired: _amount0Desired,
                    amount1Desired: _amount1Desired,
                    amount0Min: _amount0Min,
                    amount1Min: _amount1Min,
                    deadline: _deadline
                })
            );
    }

    /**
     * @notice Decreases liquidity in an existing Uniswap V3 position.
     * @param s The storage reference for the pool position.
     * @param _liquidity The amount of liquidity to remove.
     * @param _amount0Min The minimum amount of currency0 to remove.
     * @param _amount1Min The minimum amount of currency1 to remove.
     * @param _deadline The deadline by which the decrease must be completed.
     * @return amount0 The amount of currency0 removed.
     * @return amount1 The amount of currency1 removed.
     */
    function decrease(
        Storage storage s,
        uint128 _liquidity,
        uint256 _amount0Min,
        uint256 _amount1Min,
        uint256 _deadline
    ) external returns (uint256 amount0, uint256 amount1) {
        if (_liquidity == 0) {
            return (0, 0);
        }
        //slither-disable-next-line reentrancy-no-eth,locked-ether
        (amount0, amount1) = INonfungiblePositionManager(
            s.i_nonfungiblePositionManager
        ).decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: s.tokenId,
                    liquidity: _liquidity,
                    amount0Min: _amount0Min,
                    amount1Min: _amount1Min,
                    deadline: _deadline
                })
            );
    }

    /**
     * @notice Collects fees from an existing Uniswap V3 position.
     * @param s The storage reference for the pool position.
     * @param _recipient The address to receive the collected fees.
     * @param _amount0Max The maximum amount of currency0 to collect.
     * @param _amount1Max The maximum amount of currency1 to collect.
     * @return amount0 The amount of currency0 collected.
     * @return amount1 The amount of currency1 collected.
     */
    function collect(
        Storage storage s,
        address _recipient,
        uint128 _amount0Max,
        uint128 _amount1Max
    ) external returns (uint256 amount0, uint256 amount1) {
        if (_amount0Max == 0 && _amount1Max == 0) {
            return (0, 0);
        }

        //slither-disable-next-line reentrancy-no-eth,locked-ether
        (amount0, amount1) = INonfungiblePositionManager(
            s.i_nonfungiblePositionManager
        ).collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: s.tokenId,
                    recipient: _recipient,
                    amount0Max: _amount0Max,
                    amount1Max: _amount1Max
                })
            );
    }

    /**
     * @notice Executes a single-hop swap on Uniswap V3.
     * @param _swapRouter The Uniswap V3 swap router.
     * @param _tokenIn The token to swap from.
     * @param _tokenOut The token to swap to.
     * @param _amountIn The amount of token to swap.
     * @param _recipient The address to receive the swapped tokens.
     * @param _fee The fee tier of the pool to swap through.
     * @param _amountOutMinimum The minimum amount of token to receive.
     * @return amountOut The amount of token received.
     */
    function exactInputSingleSwap(
        IV3SwapRouter _swapRouter,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _recipient,
        uint24 _fee,
        uint256 _amountOutMinimum
    ) external returns (uint256 amountOut) {
        IERC20(_tokenIn).forceApprove(address(_swapRouter), _amountIn);

        try
            _swapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: _tokenIn,
                    tokenOut: _tokenOut,
                    fee: _fee,
                    recipient: _recipient,
                    amountIn: _amountIn,
                    amountOutMinimum: _amountOutMinimum,
                    sqrtPriceLimitX96: 0
                })
            )
        returns (uint256 _amountOut) {
            return _amountOut;
        } catch Error(string memory reason) {
            string memory message = string.concat("swap failed: ", reason);
            revert(message);
        } catch (bytes memory) {
            revert("swap failed");
        }
    }

    /**
     * @notice Executes a multi-hop swap on Uniswap V3.
     * @param _swapRouter The Uniswap V3 swap router.
     * @param _tokenIn The token to swap from.
     * @param _path The swap path.
     * @param _amountIn The amount of token to swap.
     * @param _recipient The address to receive the swapped tokens.
     * @param _amountOutMinimum The minimum amount of token to receive.
     * @return amountOut The amount of token received.
     */
    function exactInputMultihopSwap(
        IV3SwapRouter _swapRouter,
        address _tokenIn,
        bytes memory _path,
        uint256 _amountIn,
        address _recipient,
        uint256 _amountOutMinimum
    ) external returns (uint256 amountOut) {
        // aderyn-ignore-next-line(deprecated-oz-functions)
        TransferHelper.safeApprove(_tokenIn, address(_swapRouter), _amountIn);
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
            .ExactInputParams({
                path: _path,
                recipient: _recipient,
                amountIn: _amountIn,
                amountOutMinimum: _amountOutMinimum
            });
        try _swapRouter.exactInput(params) returns (uint256 _amountOut) {
            return _amountOut;
        } catch Error(string memory reason) {
            string memory message = string.concat("swap failed: ", reason);
            revert(message);
        } catch (bytes memory) {
            revert("swap failed");
        }
    }

    /**
     * @notice Retrieves information about a Uniswap V3 pool position.
     * @param _poolPartyPosition The pool party position.
     * @return amount0 The amount of currency0 in the position.
     * @return amount1 The amount of currency1 in the position.
     * @return liquidity The amount of liquidity in the position at uniswap.
     * @return tokensOwed0 The amount of currency0 owed.
     * @return tokensOwed1 The amount of currency1 owed.
     */
    function getPoolPositionInfo(
        IPoolPartyPosition _poolPartyPosition
    )
        external
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidity,
            uint256 tokensOwed0,
            uint256 tokensOwed1
        )
    {
        uint256 tokenId = _poolPartyPosition.poolPositionView().tokenId();
        INonfungiblePositionManager nonfungiblePositionManager = _poolPartyPosition
                .poolPositionView()
                .nonfungiblePositionManager();

        //slither-disable-next-line unused-return,reentrancy-no-eth
        (, , , , , , , liquidity, , , , ) = nonfungiblePositionManager
            .positions(tokenId);

        // if liquidity is 0, it means the position has been closed. Then we already collected the all fees
        if (liquidity == 0) {
            return (0, 0, 0, 0, 0);
        }

        (tokensOwed0, tokensOwed1) = PositionValue.fees(
            nonfungiblePositionManager,
            tokenId
        );

        (amount0, amount1) = getAmountsFromLiquidity(
            _poolPartyPosition,
            liquidity
        );
    }

    /**
     * @notice Calculates the amounts of currency0 and currency1 from a given liquidity amount.
     * @param _poolPartyPosition The pool party position.
     * @param _liquidity The amount of liquidity.
     * @return amount0 The amount of currency0.
     * @return amount1 The amount of currency1.
     */
    function getAmountsFromLiquidity(
        IPoolPartyPosition _poolPartyPosition,
        uint128 _liquidity
    ) public view returns (uint256 amount0, uint256 amount1) {
        if (_liquidity == 0) {
            return (0, 0);
        }

        PositionKey memory positionKey = _poolPartyPosition
            .poolPositionView()
            .key();

        //slither-disable-next-line unused-return
        (uint160 sqrtPriceX96Pool, , , , , , ) = IUniswapV3Pool(
            positionKey.pool
        ).slot0();

        uint160 sqrtPriceX96BeforeClose = _poolPartyPosition
            .poolPositionView()
            .sqrtPriceX96BeforeClose();

        if (
            _poolPartyPosition.poolPositionView().isClosed() &&
            sqrtPriceX96BeforeClose > 0
        ) {
            sqrtPriceX96Pool = sqrtPriceX96BeforeClose;
        }

        uint256 tokenId = _poolPartyPosition.poolPositionView().tokenId();

        //slither-disable-next-line unused-return
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            ,
            ,
            ,
            ,

        ) = _poolPartyPosition
                .poolPositionView()
                .nonfungiblePositionManager()
                .positions(tokenId);
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96Pool,
            sqrtRatioAX96,
            sqrtRatioBX96,
            _liquidity
        );
    }

    /**
     * @notice Calculates the liquidity from given amounts of currency0 and currency1.
     * @param _poolPartyPosition The pool party position.
     * @param _amount0 The amount of currency0.
     * @param _amount1 The amount of currency1.
     * @return liquidity0 The liquidity for currency0.
     * @return liquidity1 The liquidity for currency1.
     */
    function getLiquidityFromAmounts(
        IPoolPartyPosition _poolPartyPosition,
        uint256 _amount0,
        uint256 _amount1
    ) external view returns (uint128 liquidity0, uint128 liquidity1) {
        PositionKey memory positionKey = _poolPartyPosition
            .poolPositionView()
            .key();

        //slither-disable-next-line unused-return
        (uint160 sqrtRatioX96, , , , , , ) = IUniswapV3Pool(positionKey.pool)
            .slot0();

        uint256 tokenId = _poolPartyPosition.poolPositionView().tokenId();
        uint160 sqrtPriceX96BeforeClose = _poolPartyPosition
            .poolPositionView()
            .sqrtPriceX96BeforeClose();

        if (
            _poolPartyPosition.poolPositionView().isClosed() &&
            sqrtPriceX96BeforeClose > 0
        ) {
            sqrtRatioX96 = sqrtPriceX96BeforeClose;
        }

        //slither-disable-next-line unused-return
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            ,
            ,
            ,
            ,

        ) = _poolPartyPosition
                .poolPositionView()
                .nonfungiblePositionManager()
                .positions(tokenId);
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                sqrtRatioAX96,
                sqrtRatioBX96,
                _amount0
            );
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                sqrtRatioX96,
                sqrtRatioBX96,
                _amount0
            );
            liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioX96,
                _amount1
            );
        } else {
            liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioBX96,
                _amount1
            );
        }
    }

    /**
     * @notice Calculates the liquidity from a fixed sqrt price and given amounts of currency0 and currency1.
     * @param amount0 The amount of currency0.
     * @param amount1 The amount of currency1.
     * @return liquidity The liquidity for the given amounts.
     */
    function getLiquidityFromFixedSqrtPrice(
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint128 liquidity) {
        if (amount0 == 0 && amount1 == 0) {
            return 0;
        }
        uint160 sqrtRatioX96 = 79228162514264337593543950336; // we set the price of the pool to the 1:1
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(
            int24(TickMath.MIN_TICK)
        );
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(
            int24(TickMath.MAX_TICK)
        );

        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        if (sqrtRatioX96 <= sqrtRatioAX96 && amount0 > 0) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount0
            );
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = 0;
            uint128 liquidity1 = 0;
            if (amount0 > 0) {
                liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                    sqrtRatioX96,
                    sqrtRatioBX96,
                    amount0
                );
            }
            if (amount1 > 0) {
                liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                    sqrtRatioAX96,
                    sqrtRatioX96,
                    amount1
                );
            }
            liquidity = liquidity0 + liquidity1;
        } else if (amount1 > 0) {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(
                sqrtRatioAX96,
                sqrtRatioBX96,
                amount1
            );
        }
    }
}
