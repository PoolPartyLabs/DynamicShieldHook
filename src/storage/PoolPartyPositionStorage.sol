// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {Extsload} from "../base/Extsload.sol";
import {IPoolPartyPositionManager} from "../interfaces/IPoolPartyPositionManager.sol";
import {TickMath} from "../library/uniswap/TickMath.sol";
import {Errors} from "../interfaces/Errors.sol"; 
import {Extsload} from "../base/Extsload.sol";
import "../interfaces/Constants.sol";
import "../interfaces/IPoolPartyPosition.sol";

struct Storage {
    address i_factory; // 0
    address i_nonfungiblePositionManager;
    address i_uniswapV3SwapRouter;
    address i_uniswapV3Factory;
    address i_snapshotManager;
    address i_refundVaultManager;
    address i_feesVaultManager; // 6
    address i_WETH9;
    address i_stableCurrency;
    address i_poolPartyRecipient;
    address i_currency0;
    address i_currency1;
    address i_manager;
    address i_operator; // 13
    address i_poolPositionView; // 14
    uint24 i_operatorFee; // 14
    uint24 i_protocolFee; // 14
    uint24 i_fee; // 14
    PositionKey positionKey; // 15
    int24 currentTickLower; // 20
    int24 currentTickUpper; // 20
    uint256 tokenId; // 21
    uint256 version;
    mapping(PositionId => mapping(uint256 tokenId => bool)) isOpen;
    mapping(address => uint128) operatorMintLiquidity;
    mapping(address => uint128) uniswapLiquidityOf;
    mapping(address => uint128) liquidityOf;
    mapping(address => uint256) earned0Of; // 27
    mapping(address => uint256) earned1Of; // 28
    mapping(address => uint256) rewardIndex0Of; // 29
    mapping(address => uint256) rewardIndex1Of; // 30
    uint256 rewardIndex0; // 31
    uint256 rewardIndex1; // 32
    uint256 totalLiquidityInStableCurrency;
    uint256 totalCollectedFeesInStableCurrency;
    uint256 totalRefundInStableCurrency;
    uint256 liquidityForCollectedFees; // 36
    uint128 liquidity; // 37
    uint128 uniswapLiquidity; // 37
    uint128 remainingLiquidityAfterClose; // 38
    uint128 liquidityBeforeClose; // 38
    uint128 uniswapLiquidityBeforeClose; // 39
    uint160 sqrtPriceX96BeforeClose; // 40
    bool isAllLiquiditySwappedToStableCurrency; // 40
    bool isMovingRange; // 40
}

abstract contract PoolPartyPositionStorage is
    IPoolPartyPosition,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    Extsload
{
    using PositionIdLib for PositionKey;

    // slither-disable-next-line uninitialized-state,reentrancy-no-eth
    Storage internal s;

    // slither-disable-next-line incorrect-modifier
    modifier whenManagerNotDestroyed() {
        bool destroyed = IPoolPartyPositionManager(s.i_manager).isDestroyed();
        require(!destroyed, Errors.IsDestroyed());
        _;
    }

    // slither-disable-next-line incorrect-modifier
    modifier whenManagerNotPaused() {
        bool paused = PausableUpgradeable(s.i_manager).paused();
        require(!paused, Errors.PoolPositionPaused());
        _;
    }

    // slither-disable-next-line incorrect-modifier
    modifier whenNotMovingRange() {
        require(!s.isMovingRange, Errors.PoolPositionMovingRange());
        _;
    }

    // aderyn-ignore-next-line
    function initialize(
        ConstructorParams memory _params,
        address _factory
    ) external initializer {
        require(
            _params.currency0 != address(0) && _params.currency1 != address(0),
            Errors.CurrencyMustNotBeZero(_params.currency0, _params.currency1)
        );
        require(
            _params.currency0 != _params.currency1,
            Errors.CurrencyMustNotBeEqual(_params.currency0, _params.currency1)
        );
        require(
            _params.fee == 1e2 ||
                _params.fee == 5e2 ||
                _params.fee == 3e3 ||
                _params.fee == 10e3,
            Errors.InvalidFee(_params.fee)
        );
        require(
            _params.operatorFee >= MIN_OPERATOR_FEE &&
                _params.operatorFee <= MAX_OPERATOR_FEE,
            Errors.InvalidOperatorFee(_params.operatorFee)
        );
        require(_params.operator != address(0), Errors.AddressIsZero());
        require(
            _params.protocolFee >= MIN_PROTOCOL_FEE &&
                _params.protocolFee <= MAX_PROTOCOL_FEE,
            Errors.InvalidProtocolFee(_params.protocolFee)
        );
        require(
            _params.protocolFeeRecipient != address(0),
            Errors.AddressIsZero()
        );
        require(
            _params.uniswapV3SwapRouter != address(0),
            Errors.AddressIsZero()
        );
        require(_params.uniswapV3Factory != address(0), Errors.AddressIsZero());
        require(
            _params.nonfungiblePositionManager != address(0),
            Errors.AddressIsZero()
        );
        require(_params.manager != address(0), Errors.AddressIsZero());
        require(_params.upgrader != address(0), Errors.AddressIsZero());

        require(
            _params.tickLower < _params.tickUpper,
            Errors.TickLowerMustBeLessThanTickUpper(
                _params.tickLower,
                _params.tickUpper
            )
        );
        require(
            _params.tickLower >= TickMath.MIN_TICK &&
                _params.tickUpper <= TickMath.MAX_TICK,
            Errors.TicksMustBeWithinBounds(_params.tickLower, _params.tickUpper)
        );
        require(_params.stableCurrency != address(0), Errors.AddressIsZero());
        require(_params.WETH9 != address(0), Errors.AddressIsZero());

        __AccessControlDefaultAdminRules_init(3 days, _params.admin);

        address _pool = IUniswapV3Factory(_params.uniswapV3Factory).getPool(
            _params.currency0,
            _params.currency1,
            _params.fee
        );

        require(_pool != address(0), Errors.PoolPositionNotFound());

        //slither-disable-next-line unused-return
        (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(_pool)
            .slot0();

        require(sqrtPriceX96Existing != 0, Errors.PoolNotInitialized());

        PositionKey memory _positionKey = PositionKey({
            pool: _pool,
            operator: _params.operator,
            operatorFee: _params.operatorFee,
            currency0: _params.currency0,
            currency1: _params.currency1,
            fee: _params.fee,
            tickLower: _params.tickLower,
            tickUpper: _params.tickUpper,
            name: keccak256(abi.encodePacked(_params.name))
        });
        PositionId positionId = _positionKey.toId();

        require(
            !s.isOpen[positionId][s.tokenId],
            Errors.PoolPositionAlreadyClosed()
        );

        s.i_factory = _factory;
        s.i_nonfungiblePositionManager = _params.nonfungiblePositionManager;
        s.i_uniswapV3SwapRouter = _params.uniswapV3SwapRouter;
        s.i_uniswapV3Factory = _params.uniswapV3Factory;
        s.i_WETH9 = _params.WETH9;
        s.i_stableCurrency = _params.stableCurrency;
        s.i_manager = _params.manager;
        s.i_poolPartyRecipient = _params.protocolFeeRecipient;
        s.i_protocolFee = _params.protocolFee;
        s.i_operator = _params.operator;
        s.i_operatorFee = _params.operatorFee;
        s.i_currency0 = _params.currency0;
        s.i_currency1 = _params.currency1;
        s.i_fee = _params.fee;
        s.positionKey = _positionKey;
        s.version = 1;
        s.currentTickLower = _params.tickLower;
        s.currentTickUpper = _params.tickUpper;

        _grantRole(MANAGER_ROLE, _params.manager);
        _grantRole(UPGRADER_ROLE, _params.upgrader);
        _grantRole(FACTORY_ROLE, _factory);
    }

    // aderyn-ignore-next-line
    function setupVaultsAndSnapshotManagers(
        address _refundVaultManager,
        address _feesVaultManager,
        address _snaphshotManager
    )
        external
        // aderyn-ignore-next-line(centralization-risk)
        onlyRole(FACTORY_ROLE)
    {
        if (
            s.i_refundVaultManager != address(0) ||
            s.i_feesVaultManager != address(0) ||
            s.i_snapshotManager != address(0)
        ) {
            revert Errors.VaultsAndSnapshotManagersAlreadySet();
        }
        s.i_refundVaultManager = _refundVaultManager;
        s.i_feesVaultManager = _feesVaultManager;
        s.i_snapshotManager = _snaphshotManager;
    }

    // aderyn-ignore-next-line(state-variable-changes-without-events)
    function setupPoolPositionView(
        address _poolPositionView
    )
        external
        // aderyn-ignore-next-line(centralization-risk)
        onlyRole(FACTORY_ROLE)
    {
        require(_poolPositionView != address(0), Errors.AddressIsZero());
        s.i_poolPositionView = _poolPositionView;
    }

    function poolPositionView() external view returns (IPoolPartyPositionView) {
        return IPoolPartyPositionView(s.i_poolPositionView);
    }
}
