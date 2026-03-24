// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CLAWDStakeV2
/// @notice Tiered staking contract for CLAWD token on Base.
/// Users lock a fixed CLAWD amount into one of three tiers for 180 days,
/// earning 5% yield while 5% is burned from the house reserve.
contract CLAWDStakeV2 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════
    //                       CONSTANTS
    // ═══════════════════════════════════════════════════════

    uint256 public constant LOCK_DURATION = 180 days;
    uint256 public constant YIELD_BPS = 500; // 5%
    uint256 public constant BURN_BPS = 500;  // 5%
    uint256 public constant BPS_DENOMINATOR = 10_000;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // ═══════════════════════════════════════════════════════
    //                       STRUCTS
    // ═══════════════════════════════════════════════════════

    struct Tier {
        uint256 stakeAmount;
        uint256 maxSlots;
        uint256 usedSlots;
    }

    struct StakeInfo {
        uint8 tierIndex;
        uint256 stakeAmount;
        uint256 stakedAt;
    }

    // ═══════════════════════════════════════════════════════
    //                       STATE
    // ═══════════════════════════════════════════════════════

    IERC20 public immutable clawdToken;

    mapping(uint8 => Tier) public tiers;
    mapping(address => StakeInfo[]) public stakes;

    uint256 public houseReserve;

    // ═══════════════════════════════════════════════════════
    //                       EVENTS
    // ═══════════════════════════════════════════════════════

    event Stake(address indexed user, uint8 tierIndex, uint256 stakedAt);
    event Unstake(address indexed user, uint256 stakeIndex, uint256 principal, uint256 yield_, uint256 burn);
    event HouseFunded(uint256 amount);
    event TierUpdated(uint8 tierIndex, uint256 stakeAmount, uint256 maxSlots);

    // ═══════════════════════════════════════════════════════
    //                       ERRORS
    // ═══════════════════════════════════════════════════════

    error InvalidTier();
    error TierFull();
    error LockNotExpired();
    error InvalidStakeIndex();
    error InsufficientHouseReserve();
    error ZeroAmount();

    // ═══════════════════════════════════════════════════════
    //                     CONSTRUCTOR
    // ═══════════════════════════════════════════════════════

    constructor(address _clawdToken, address _owner) Ownable(_owner) {
        clawdToken = IERC20(_clawdToken);

        // Initialize default tiers
        tiers[0] = Tier({ stakeAmount: 13_030_000e18, maxSlots: 100, usedSlots: 0 });
        tiers[1] = Tier({ stakeAmount: 25_030_000e18, maxSlots: 20,  usedSlots: 0 });
        tiers[2] = Tier({ stakeAmount: 130_030_000e18, maxSlots: 10, usedSlots: 0 });

        emit TierUpdated(0, 13_030_000e18, 100);
        emit TierUpdated(1, 25_030_000e18, 20);
        emit TierUpdated(2, 130_030_000e18, 10);
    }

    // ═══════════════════════════════════════════════════════
    //                     EXTERNAL — USER
    // ═══════════════════════════════════════════════════════

    /// @notice Stake CLAWD tokens into a tier.
    /// @param tierIndex The tier to stake into (0, 1, or 2).
    function stake(uint8 tierIndex) external nonReentrant {
        Tier storage tier = tiers[tierIndex];
        if (tier.stakeAmount == 0) revert InvalidTier();
        if (tier.usedSlots >= tier.maxSlots) revert TierFull();

        uint256 amount = tier.stakeAmount;

        // Check house reserve can cover yield + burn for this stake
        uint256 yieldAmount = (amount * YIELD_BPS) / BPS_DENOMINATOR;
        uint256 burnAmount = (amount * BURN_BPS) / BPS_DENOMINATOR;
        if (houseReserve < yieldAmount + burnAmount) revert InsufficientHouseReserve();

        // Effects
        tier.usedSlots += 1;
        stakes[msg.sender].push(StakeInfo({
            tierIndex: tierIndex,
            stakeAmount: amount,
            stakedAt: block.timestamp
        }));

        // Interactions
        clawdToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Stake(msg.sender, tierIndex, block.timestamp);
    }

    /// @notice Unstake CLAWD tokens after the lock period.
    /// @param stakeIndex The index of the stake in the user's stakes array.
    function unstake(uint256 stakeIndex) external nonReentrant {
        StakeInfo[] storage userStakes = stakes[msg.sender];
        if (stakeIndex >= userStakes.length) revert InvalidStakeIndex();

        StakeInfo memory stakeInfo = userStakes[stakeIndex];
        if (block.timestamp < stakeInfo.stakedAt + LOCK_DURATION) revert LockNotExpired();

        uint256 principal = stakeInfo.stakeAmount;
        uint256 yieldAmount = (principal * YIELD_BPS) / BPS_DENOMINATOR;
        uint256 burnAmount = (principal * BURN_BPS) / BPS_DENOMINATOR;

        if (houseReserve < yieldAmount + burnAmount) revert InsufficientHouseReserve();

        // Effects — remove stake via swap-and-pop
        uint256 lastIndex = userStakes.length - 1;
        if (stakeIndex != lastIndex) {
            userStakes[stakeIndex] = userStakes[lastIndex];
        }
        userStakes.pop();

        // Decrement used slots
        tiers[stakeInfo.tierIndex].usedSlots -= 1;

        // Deduct from house reserve
        houseReserve -= (yieldAmount + burnAmount);

        // Interactions — send principal + yield to user
        clawdToken.safeTransfer(msg.sender, principal + yieldAmount);

        // Burn from house reserve
        clawdToken.safeTransfer(BURN_ADDRESS, burnAmount);

        emit Unstake(msg.sender, stakeIndex, principal, yieldAmount, burnAmount);
    }

    // ═══════════════════════════════════════════════════════
    //                    EXTERNAL — OWNER
    // ═══════════════════════════════════════════════════════

    /// @notice Fund the house reserve with CLAWD tokens.
    /// @param amount Amount of CLAWD to deposit.
    function fundHouseReserve(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        houseReserve += amount;
        clawdToken.safeTransferFrom(msg.sender, address(this), amount);

        emit HouseFunded(amount);
    }

    /// @notice Update tier parameters. Does NOT affect existing active stakes.
    /// @param tierIndex The tier to update (0, 1, or 2).
    /// @param stakeAmount New stake amount for the tier.
    /// @param maxSlots New max slots for the tier.
    function setTier(uint8 tierIndex, uint256 stakeAmount, uint256 maxSlots) external onlyOwner {
        if (tierIndex > 2) revert InvalidTier();

        Tier storage tier = tiers[tierIndex];
        // maxSlots must be >= usedSlots to not break existing stakes
        require(maxSlots >= tier.usedSlots, "maxSlots < usedSlots");

        tier.stakeAmount = stakeAmount;
        tier.maxSlots = maxSlots;

        emit TierUpdated(tierIndex, stakeAmount, maxSlots);
    }

    /// @notice Withdraw excess house reserve tokens.
    /// @param amount Amount of CLAWD to withdraw.
    function withdrawHouseReserve(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (amount > houseReserve) revert InsufficientHouseReserve();

        houseReserve -= amount;
        clawdToken.safeTransfer(msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════
    //                       VIEW
    // ═══════════════════════════════════════════════════════

    /// @notice Get all stakes for a user.
    function getStakes(address user) external view returns (StakeInfo[] memory) {
        return stakes[user];
    }

    /// @notice Get the number of stakes for a user.
    function getStakeCount(address user) external view returns (uint256) {
        return stakes[user].length;
    }

    /// @notice Get tier info.
    function getTier(uint8 tierIndex) external view returns (Tier memory) {
        return tiers[tierIndex];
    }
}
