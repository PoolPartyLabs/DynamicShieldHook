// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PositionKey} from "../types/PositionKey.sol";
import {PositionId, PositionIdLib} from "../types/PositionId.sol";
import {IPoolPartyPositionView, IPoolPartyPositionViewStructs} from "./IPoolPartyPositionView.sol";
import {IExtsload} from "./IExtsload.sol";

interface IPoolPartyPositionEvents {
    /// @notice Emitted when a position's is created
    /// @param operator The address of the operator for a specific pool
    /// @param tokenId The ID of the pool position is being created
    /// @param positionId The id of the position for which pool position is created
    /// @param position The address of the position for which pool position is created
    event PositionCreated(
        address indexed operator,
        uint256 indexed tokenId,
        PositionId indexed positionId,
        address position
    );

    /// @notice Emitted when a position's liquidity is added
    /// @param investor The Owner of the position for which liquidity is added
    /// @param positionId The id of the position for which liquidity is added
    /// @param liquidity The amount of liquidity added
    /// @param amount0 The amount of currency0 added
    /// @param amount1 The amount of currency1 added
    // aderyn-ignore-next-line(unindexed-events)
    event LiquidityAdded(
        address indexed investor,
        PositionId indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when a position's liquidity is removed
    /// @dev Does not withdraw any fees earned by the liquidity position, which must be withdrawn via #collect
    /// @param investor The Owner of the position for which liquidity is removed
    /// @param positionId The id of the position for which liquidity is removed
    /// @param liquidity The amount of liquidity removed
    /// @param amount0 The amount of currency0 removed
    /// @param amount1 The amount of currency1 removed
    // aderyn-ignore-next-line(unindexed-events)
    event LiquidityRemoved(
        address indexed investor,
        PositionId indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when rewards are collected by the owner of a position
    /// @param investor The Owner of the position for which rewards are collected
    /// @param positionId The id of the position for which rewards are collected
    /// @param amount0 The amount of currency0 fees collected
    /// @param amount1 The amount of currency1 fees collected
    // aderyn-ignore-next-line(unindexed-events)
    event RewardsCollected(
        address indexed investor,
        PositionId indexed positionId,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when all rewards are collected by the position
    /// @param positionId The id of the position for which rewards are collected
    /// @param amount0 The amount of currency0 fees collected
    /// @param amount1 The amount of currency1 fees collected
    // aderyn-ignore-next-line(unindexed-events)
    event AllRewardsCollected(
        PositionId indexed positionId,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when a position is closed
    /// @param positionId The id of the position for which pool position is closed
    /// @param position The address of the position for which pool position is closed
    /// @param liquidity The amount of liquidity removed
    /// @param amount0 The amount of currency0 removed
    /// @param amount1 The amount of currency1 removed
    // aderyn-ignore-next-line(unindexed-events)
    event PositionClosed(
        PositionId indexed positionId,
        address indexed position,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when a position is withdrawn
    /// @param investor The Owner of the position for which rewards are collected
    /// @param amount0 The amount of currency0 plus the fees collected
    /// @param amount1 The amount of currency1 plus the fees collected
    // aderyn-ignore-next-line(unindexed-events)
    event Withdrawn(
        address indexed investor,
        PositionId indexed positionId,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when a position's rewards are collected
    /// @param positionId The id of the position for which rewards are collected
    /// @param amount0 The amount of currency0 fees collected
    /// @param amount1 The amount of currency1 fees collected
    // aderyn-ignore-next-line(unindexed-events)
    event PositionRewardsCollected(
        PositionId indexed positionId,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when rewards are collected by the owner of a position in StableCurrency
    /// @param investor The Owner of the position for which rewards are collected
    /// @param positionId The id of the position for which rewards are collected
    /// @param amountStableCurrency The amount of fees collected in StableCurrency
    // aderyn-ignore-next-line(unindexed-events)
    event RewardsCollectedInStableCurrency(
        address indexed investor,
        PositionId indexed positionId,
        uint256 amountStableCurrency
    );

    /// @notice Emitted when a position is withdrawn in StableCurrency
    /// @param investor The Owner of the position for which rewards are collected
    /// @param stableCurrencyAmount The amount plus the fees collected in StableCurrency
    // aderyn-ignore-next-line(unindexed-events)
    event WithdrawnInStableCurrency(
        address indexed investor,
        PositionId indexed positionId,
        uint256 stableCurrencyAmount
    );
}

interface IPoolPartyPositionStructs {
    struct ConstructorParams {
        // @param The address of the admin
        address admin;
        /// @param The address of the upgrader
        address upgrader;
        /// @param The address of the manager
        address manager;
        /// @param The address of the INonfungiblePositionManager
        address nonfungiblePositionManager;
        /// @param The address of the Uniswap V3 Factory
        address uniswapV3Factory;
        /// @param The address of the Uniswap V3 Swap Router
        address uniswapV3SwapRouter;
        /// @param The address of the WETH9 token
        address WETH9;
        /// @param The address of the StableCurrency token
        address stableCurrency;
        /// @param The address of the poolParty recipient
        address protocolFeeRecipient;
        /// @param The address of the operator for a specific pool
        address operator;
        /// @param The address of the currency0 for a specific pool
        address currency0;
        /// @param The address of the currency1 for a specific pool
        address currency1;
        /// @param The fee associated with the pool: 100 (0,01%), 500 (0,05%), 3000 (0,3%), or 10000 (1%)
        uint24 fee;
        /// @param tickLower The lower end of the tick range for the position
        int24 tickLower;
        /// @param tickUpper The higher end of the tick range for the position
        int24 tickUpper;
        /// @param The operator fee associated with the pool: between 1000 (10%) and 10000 (100%)
        uint24 operatorFee;
        /// @param The pool party fee associated with the pool: between 1000 (10%) and 10000 (100%)
        uint24 protocolFee;
        /// @notice Sets the initial price for the pool
        /// @dev Price is represented as a sqrt(amountCurrency1/amountCurrency0) Q64.96 value
        /// @param sqrtPriceX96 the initial sqrt price of the pool as a Q64.96
        // uint160 sqrtPriceX96;
        /// @param The name of the pool
        string name;
    }

    struct MintPositionParams {
        /// @param amount0Desired The desired amount of currency0 to be spent
        uint256 amount0Desired;
        /// @param amount1Desired The desired amount of currency1 to be spent
        uint256 amount1Desired;
        /// @notice Must be calculated in the client side to adjust for slippage tolerance.
        /// @param amount0Min The minimum amount of currency0 to spend, which serves as a slippage check
        uint256 amount0Min;
        /// @notice Must be calculated in the client side to adjust for slippage tolerance.
        /// @param amount1Min The minimum amount of currency1 to spend, which serves as a slippage check
        uint256 amount1Min;
        /// @param deadline The time by which the transaction must be included to effect the change
        uint256 deadline;
    }

    struct SwapParams {
        /// @param shouldSwapFees The flag to collect fees and swap to StableCurrency
        bool shouldSwapFees;
        /// @notice Must be calculated in the client side to adjust for slippage tolerance.
        /// @param amount0OutMinimum The minimum amount of currency0 to spend, which serves as a slippage check
        uint256 amount0OutMinimum;
        /// @notice Must be calculated in the client side to adjust for slippage tolerance.
        /// @param amount1Min The minimum amount of currency1 to spend, which serves as a slippage check
        uint256 amount1OutMinimum;
        /// @param multihopSwapPath0 The
        bytes multihopSwapPath0;
        /// @param multihopSwapPath1 The
        bytes multihopSwapPath1;
        /// @param multihopSwapRefundPath0 The
        bytes multihopSwapRefundPath0;
        /// @param multihopSwapRefundPath1 The
        bytes multihopSwapRefundPath1;
    }

    struct SwapAllToStableCurrencyParams {
        /// @param swapAllToStableCurrency The flag to collect fees and an tokens swap to StableCurrency
        bool swapAllToStableCurrency;
        /// @notice Must be calculated in the client side to adjust for slippage tolerance.
        /// @param amount0OutMinimum The minimum amount of currency0 to spend, which serves as a slippage check
        uint256 amount0OutMinimum;
        /// @notice Must be calculated in the client side to adjust for slippage tolerance.
        /// @param amount1OutMinimum The minimum amount of currency1 to spend, which serves as a slippage check
        uint256 amount1OutMinimum;
        /// @param multihopSwapPath0 The
        bytes multihopSwapPath0;
        /// @param multihopSwapPath1 The
        bytes multihopSwapPath1;
    }

    struct IncreaseLiquidityParams {
        /// @param investor The Owner of the position for which liquidity is added
        address investor;
        /// @param amount0StableCurrency The desired amount of StableCurrency to be spent on currency0
        uint256 amount0StableCurrency;
        /// @param amount1StableCurrency The desired amount of StableCurrency to be spent on currency1
        uint256 amount1StableCurrency;
        /// @param ignoreSlippage The flag to ignore slippage tolerance
        bool ignoreSlippage;
        /// @param deadline The time by which the transaction must be included to effect the change
        uint256 deadline;
        /// @param swap The params necessary to swap from StableCurrency to currency0 and currency1, encoded as `SwapParams` in calldata
        SwapParams swap;
    }

    struct DecreaseLiquidityParams {
        /// @param investor The Owner of the position for which liquidity is removed
        address investor;
        /// @notice Must be calculated in the client side to adjust for slippage tolerance.
        /// @param amount0Min The minimum amount of currency0 to spend, which serves as a slippage check
        uint256 amount0Min;
        /// @notice Must be calculated in the client side to adjust for slippage tolerance.
        /// @param amount1Min The minimum amount of currency1 to spend, which serves as a slippage check
        uint256 amount1Min;
        /// @param deadline The time by which the transaction must be included to effect the change
        uint256 deadline;
        /// @param percentage The percentage of liquidity to be removed
        /// @dev The percentage is represented as 1e15 (1%) - 100e15 (100%)
        uint256 percentage;
        /// @param swap The params necessary to swap to StableCurrency, encoded as `SwapParams` in calldata
        SwapParams swap;
        /// @param swapAllToStableCurrency The params necessary to swap all to StableCurrency, encoded as `SwapAllToStableCurrencyParams` in calldata
        SwapAllToStableCurrencyParams swapAllToStableCurrency;
    }

    struct ClosePositionParams {
        /// @param operator The address of the operator for a specific pool
        address operator;
        /// @param deadline The time by which the transaction must be included to effect the change
        uint256 deadline;
        /// @param swapAllToStableCurrency The params necessary to swap all to StableCurrency, encoded as `SwapAllToStableCurrencyParams` in calldata
        SwapAllToStableCurrencyParams swapAllToStableCurrency;
    }

    struct CollectParams {
        /// @param investor The Owner of the position for which rewards are collected
        address investor;
        /// @param deadline The time by which the transaction must be included to effect the change
        uint256 deadline;
        /// @param swap The params necessary to swap to StableCurrency, encoded as `SwapParams` in calldata
        SwapParams swap;
    }

    struct WithdrawParams {
        /// @param investor The Owner of the position for which rewards are collected
        address investor;
        /// @param deadline The time by which the transaction must be included to effect the change
        uint256 deadline;
        /// @param swap The params necessary to swap to StableCurrency, encoded as `SwapParams` in calldata
        SwapParams swap;
    }

    struct MoveRangeParams {
        /// @param operator The address of the operator for a specific pool
        address operator;
        /// @param tickLower The lower end of the tick range for the position
        int24 tickLower;
        /// @param tickUpper The higher end of the tick range for the position
        int24 tickUpper;
        /// @param swapAmount0 The amount of currency0 to acheive resulting liquidity
        uint256 swapAmount0;
        /// @param swapAmount0Minimum The minimum amount of currency0 to spend, which serves as a slippage check
        uint256 swapAmount0Minimum;
        /// @param swapAmount1 The amount of currency1 to acheive resulting liquidity
        uint256 swapAmount1;
        /// @param swapAmount1Minimum The minimum amount of currency1 to spend, which serves as a slippage check
        uint256 swapAmount1Minimum;
        /// @param multihopSwapPath0 The path to swap currency0
        bytes multihopSwapPath0;
        /// @param multihopSwapPath1 The path to swap currency1
        bytes multihopSwapPath1;
        /// @param deadline The time by which the transaction must be included to effect the change
        uint256 deadline;
        /// @param ignoreSlippage The flag to ignore slippage tolerance
        bool ignoreSlippage;
    }
}

interface IPoolPartyPosition is
    IPoolPartyPositionEvents,
    IPoolPartyPositionStructs,
    IExtsload
{
    /// @notice Initializes the contract with the necessary parameters
    // aderyn-ignore-next-line
    function initialize(
        ConstructorParams memory _params,
        address _factory
    ) external;

    /// @notice Initializes the contract with the necessary vault and snapshot managers
    function setupVaultsAndSnapshotManagers(
        address _refundVaultManager,
        address _feesVaultManager,
        address _snaphshotManager
    ) external;

    /// @notice Initializes the contract with the necessary pool position view
    function setupPoolPositionView(address _poolPositionView) external;

    /// @notice Mints a new pool position
    /// @param _params The params necessary to create a pool position, encoded as `MintPositionParams` in calldata
    /// @return positionId The id of the position for which pool position is created
    /// @return tokenId The ID of the token's position (NFT) for which liquidity is being added
    /// @return liquidity The new liquidity amount as a result of the mint
    /// @return amount0 The amount of currency0 to acheive resulting liquidity
    /// @return amount1 The amount of currency1 to acheive resulting liquidity
    /// @dev revert if the amount0Desired or amount1Desired exceed MAX_INPUT_AMOUNT * 10 ** token.decimals()
    /// @dev event PositionCreated is emitted
    function mintPosition(
        MintPositionParams memory _params
    )
        external
        payable
        returns (
            PositionId positionId,
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    /// @param _params The params necessary to add liquidity to a pool position, encoded as `IncreaseLiquidityParams` in calldata
    /// @return liquidity The liquidity amount as a result of the increase
    /// @return amount0 The amount of currency0 to acheive resulting liquidity
    /// @return amount1 The amount of currency1 to acheive resulting liquidity
    /// @dev revert if the amount0Desired or amount1Desired exceed MAX_INPUT_AMOUNT * 10 ** token.decimals()
    /// @dev event LiquidityAdded is emitted
    function increaseLiquidity(
        IncreaseLiquidityParams calldata _params
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Decreases the amount of liquidity from a position, with tokens sent to the `investor`
    /// @param _params The params necessary to decrease liquidity from a pool position, encoded as `DecreaseLiquidityParams` in calldata
    /// @return liquidity The liquidity amount as a result of the decrease
    /// @return amount0 The amount of currency0 to acheive resulting liquidity
    /// @return amount1 The amount of currency1 to acheive resulting liquidity
    /// @dev Does not withdraw any fees earned by the liquidity position, which must be withdrawn via #collect
    /// @dev event LiquidityRemoved is emitted
    function decreaseLiquidity(
        DecreaseLiquidityParams calldata _params
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Collects up to a maximum amount of rewards owed to a specific position to the `recipient`
    /// @param _params The params necessary to collect rewards from a pool position, encoded as `CollectParams` in calldata
    /// @return amount0 The amount of currency0 fees collected
    /// @return amount1 The amount of currency1 fees collected
    /// @dev event RewardsCollected is emitted
    function collect(
        CollectParams calldata _params
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Closes a position and transfers all rewards to the recipient
    /// @param _params The params necessary to close a pool position, encoded as `ClosePositionParams` in calldata
    /// @return liquidity The liquidity amount as a result of the close
    /// @return amount0 The amount of currency0 to acheive resulting liquidity
    /// @return amount1 The amount of currency1 to acheive resulting liquidity
    /// @dev event ClosedPosition is emitted
    function closePosition(
        ClosePositionParams calldata _params
    ) external returns (uint128, uint256, uint256);

    /// @notice Withdraws all tokens and collected fees owed to a specific position to the `investor`
    /// @param _params The params necessary to withdraw from a pool position, encoded as `WithdrawParams` in calldata
    /// @return The amount of currency0
    /// @return The amount of currency1
    /// @return The net amount of currency0 fees collected
    /// @return The net amount of currency1 fees collected
    /// @dev event Withdrawn is emitted
    function withdraw(
        WithdrawParams calldata _params
    ) external returns (uint256, uint256, uint256, uint256);

    function moveRange(MoveRangeParams calldata _params) external;

    function poolPositionView() external view returns (IPoolPartyPositionView);
}
