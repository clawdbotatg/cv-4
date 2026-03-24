// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/CLAWDStakeV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Mock ERC20 for testing
contract MockCLAWD is ERC20 {
    constructor() ERC20("CLAWD", "CLAWD") {
        _mint(msg.sender, 10_000_000_000e18); // 10B supply
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract CLAWDStakeV2Test is Test {
    CLAWDStakeV2 public staking;
    MockCLAWD public token;

    address public owner = address(0xBEEF);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    uint256 constant TIER0_AMOUNT = 13_030_000e18;
    uint256 constant TIER1_AMOUNT = 25_030_000e18;
    uint256 constant TIER2_AMOUNT = 130_030_000e18;
    uint256 constant HOUSE_FUND = 500_000_000e18;

    function setUp() public {
        token = new MockCLAWD();
        staking = new CLAWDStakeV2(address(token), owner);

        // Fund users
        token.transfer(user1, 1_000_000_000e18);
        token.transfer(user2, 1_000_000_000e18);

        // Fund owner for house reserve
        token.transfer(owner, 2_000_000_000e18);

        // Owner funds house reserve
        vm.startPrank(owner);
        token.approve(address(staking), type(uint256).max);
        staking.fundHouseReserve(HOUSE_FUND);
        vm.stopPrank();

        // Users approve staking contract
        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);

        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════
    //                  CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════

    function test_constructor_setsTiers() public view {
        CLAWDStakeV2.Tier memory t0 = staking.getTier(0);
        assertEq(t0.stakeAmount, TIER0_AMOUNT);
        assertEq(t0.maxSlots, 100);
        assertEq(t0.usedSlots, 0);

        CLAWDStakeV2.Tier memory t1 = staking.getTier(1);
        assertEq(t1.stakeAmount, TIER1_AMOUNT);
        assertEq(t1.maxSlots, 20);

        CLAWDStakeV2.Tier memory t2 = staking.getTier(2);
        assertEq(t2.stakeAmount, TIER2_AMOUNT);
        assertEq(t2.maxSlots, 10);
    }

    function test_constructor_setsOwner() public view {
        assertEq(staking.owner(), owner);
    }

    // ═══════════════════════════════════════════════════════
    //                     STAKE TESTS
    // ═══════════════════════════════════════════════════════

    function test_stake_tier0() public {
        vm.prank(user1);
        staking.stake(0);

        CLAWDStakeV2.StakeInfo[] memory userStakes = staking.getStakes(user1);
        assertEq(userStakes.length, 1);
        assertEq(userStakes[0].tierIndex, 0);
        assertEq(userStakes[0].stakeAmount, TIER0_AMOUNT);
        assertEq(userStakes[0].stakedAt, block.timestamp);

        CLAWDStakeV2.Tier memory t0 = staking.getTier(0);
        assertEq(t0.usedSlots, 1);
    }

    function test_stake_tier1() public {
        vm.prank(user1);
        staking.stake(1);

        CLAWDStakeV2.StakeInfo[] memory userStakes = staking.getStakes(user1);
        assertEq(userStakes.length, 1);
        assertEq(userStakes[0].tierIndex, 1);
        assertEq(userStakes[0].stakeAmount, TIER1_AMOUNT);
    }

    function test_stake_tier2() public {
        vm.prank(user1);
        staking.stake(2);

        CLAWDStakeV2.StakeInfo[] memory userStakes = staking.getStakes(user1);
        assertEq(userStakes.length, 1);
        assertEq(userStakes[0].tierIndex, 2);
        assertEq(userStakes[0].stakeAmount, TIER2_AMOUNT);
    }

    function test_stake_multipleStakes() public {
        vm.startPrank(user1);
        staking.stake(0);
        staking.stake(0);
        staking.stake(1);
        vm.stopPrank();

        assertEq(staking.getStakeCount(user1), 3);
    }

    function test_stake_emitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit CLAWDStakeV2.Stake(user1, 0, block.timestamp);
        staking.stake(0);
    }

    function test_stake_transfersTokens() public {
        uint256 balBefore = token.balanceOf(user1);
        vm.prank(user1);
        staking.stake(0);
        uint256 balAfter = token.balanceOf(user1);
        assertEq(balBefore - balAfter, TIER0_AMOUNT);
    }

    function test_stake_revertsInvalidTier() public {
        vm.prank(user1);
        vm.expectRevert(CLAWDStakeV2.InvalidTier.selector);
        staking.stake(3);
    }

    function test_stake_revertsTierFull() public {
        // Fill all 10 slots in tier 2
        for (uint256 i = 0; i < 10; i++) {
            address staker = address(uint160(100 + i));
            token.mint(staker, TIER2_AMOUNT);
            vm.startPrank(staker);
            token.approve(address(staking), TIER2_AMOUNT);
            staking.stake(2);
            vm.stopPrank();
        }

        // 11th should fail
        vm.prank(user1);
        vm.expectRevert(CLAWDStakeV2.TierFull.selector);
        staking.stake(2);
    }

    function test_stake_revertsInsufficientReserve() public {
        // Withdraw most of the house reserve
        vm.prank(owner);
        staking.withdrawHouseReserve(HOUSE_FUND);

        vm.prank(user1);
        vm.expectRevert(CLAWDStakeV2.InsufficientHouseReserve.selector);
        staking.stake(0);
    }

    // ═══════════════════════════════════════════════════════
    //                    UNSTAKE TESTS
    // ═══════════════════════════════════════════════════════

    function test_unstake_afterLock() public {
        vm.prank(user1);
        staking.stake(0);

        // Warp past lock period
        vm.warp(block.timestamp + 180 days + 1);

        uint256 balBefore = token.balanceOf(user1);
        vm.prank(user1);
        staking.unstake(0);

        uint256 balAfter = token.balanceOf(user1);
        uint256 yieldAmount = (TIER0_AMOUNT * 500) / 10_000; // 5%
        assertEq(balAfter - balBefore, TIER0_AMOUNT + yieldAmount);

        // Stake removed
        assertEq(staking.getStakeCount(user1), 0);

        // Slot freed
        CLAWDStakeV2.Tier memory t0 = staking.getTier(0);
        assertEq(t0.usedSlots, 0);
    }

    function test_unstake_burnAmount() public {
        vm.prank(user1);
        staking.stake(0);
        vm.warp(block.timestamp + 180 days + 1);

        address burnAddr = staking.BURN_ADDRESS();
        uint256 burnBefore = token.balanceOf(burnAddr);
        vm.prank(user1);
        staking.unstake(0);
        uint256 burnAfter = token.balanceOf(burnAddr);

        uint256 burnAmount = (TIER0_AMOUNT * 500) / 10_000;
        assertEq(burnAfter - burnBefore, burnAmount);
    }

    function test_unstake_houseReserveDecreased() public {
        vm.prank(user1);
        staking.stake(0);
        vm.warp(block.timestamp + 180 days + 1);

        uint256 reserveBefore = staking.houseReserve();
        vm.prank(user1);
        staking.unstake(0);
        uint256 reserveAfter = staking.houseReserve();

        uint256 yieldAmount = (TIER0_AMOUNT * 500) / 10_000;
        uint256 burnAmount = (TIER0_AMOUNT * 500) / 10_000;
        assertEq(reserveBefore - reserveAfter, yieldAmount + burnAmount);
    }

    function test_unstake_revertsBeforeLock() public {
        vm.prank(user1);
        staking.stake(0);

        vm.prank(user1);
        vm.expectRevert(CLAWDStakeV2.LockNotExpired.selector);
        staking.unstake(0);
    }

    function test_unstake_revertsInvalidIndex() public {
        vm.prank(user1);
        vm.expectRevert(CLAWDStakeV2.InvalidStakeIndex.selector);
        staking.unstake(0);
    }

    function test_unstake_swapAndPop() public {
        // Stake 3 times in different tiers
        vm.startPrank(user1);
        staking.stake(0); // index 0
        staking.stake(1); // index 1
        staking.stake(0); // index 2
        vm.stopPrank();

        vm.warp(block.timestamp + 180 days + 1);

        // Unstake index 0 — should swap with last (index 2)
        vm.prank(user1);
        staking.unstake(0);

        CLAWDStakeV2.StakeInfo[] memory remaining = staking.getStakes(user1);
        assertEq(remaining.length, 2);
        // The last element should have moved to index 0
        assertEq(remaining[0].tierIndex, 0); // was at index 2, moved to 0
        assertEq(remaining[1].tierIndex, 1); // unchanged
    }

    function test_unstake_emitsEvent() public {
        vm.prank(user1);
        staking.stake(0);
        vm.warp(block.timestamp + 180 days + 1);

        uint256 yieldAmount = (TIER0_AMOUNT * 500) / 10_000;
        uint256 burnAmount = (TIER0_AMOUNT * 500) / 10_000;

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit CLAWDStakeV2.Unstake(user1, 0, TIER0_AMOUNT, yieldAmount, burnAmount);
        staking.unstake(0);
    }

    // ═══════════════════════════════════════════════════════
    //                 HOUSE RESERVE TESTS
    // ═══════════════════════════════════════════════════════

    function test_fundHouseReserve() public {
        uint256 additionalAmount = 100_000_000e18;
        uint256 reserveBefore = staking.houseReserve();

        vm.prank(owner);
        staking.fundHouseReserve(additionalAmount);

        assertEq(staking.houseReserve(), reserveBefore + additionalAmount);
    }

    function test_fundHouseReserve_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit CLAWDStakeV2.HouseFunded(100e18);
        staking.fundHouseReserve(100e18);
    }

    function test_fundHouseReserve_revertsZero() public {
        vm.prank(owner);
        vm.expectRevert(CLAWDStakeV2.ZeroAmount.selector);
        staking.fundHouseReserve(0);
    }

    function test_fundHouseReserve_revertsNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.fundHouseReserve(100e18);
    }

    function test_withdrawHouseReserve() public {
        uint256 reserveBefore = staking.houseReserve();
        uint256 withdrawAmount = 100_000_000e18;

        vm.prank(owner);
        staking.withdrawHouseReserve(withdrawAmount);

        assertEq(staking.houseReserve(), reserveBefore - withdrawAmount);
    }

    function test_withdrawHouseReserve_revertsExcess() public {
        vm.prank(owner);
        vm.expectRevert(CLAWDStakeV2.InsufficientHouseReserve.selector);
        staking.withdrawHouseReserve(HOUSE_FUND + 1);
    }

    function test_withdrawHouseReserve_revertsZero() public {
        vm.prank(owner);
        vm.expectRevert(CLAWDStakeV2.ZeroAmount.selector);
        staking.withdrawHouseReserve(0);
    }

    // ═══════════════════════════════════════════════════════
    //                     TIER UPDATE TESTS
    // ═══════════════════════════════════════════════════════

    function test_setTier() public {
        vm.prank(owner);
        staking.setTier(0, 20_000_000e18, 50);

        CLAWDStakeV2.Tier memory t0 = staking.getTier(0);
        assertEq(t0.stakeAmount, 20_000_000e18);
        assertEq(t0.maxSlots, 50);
    }

    function test_setTier_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit CLAWDStakeV2.TierUpdated(0, 20_000_000e18, 50);
        staking.setTier(0, 20_000_000e18, 50);
    }

    function test_setTier_revertsInvalidTier() public {
        vm.prank(owner);
        vm.expectRevert(CLAWDStakeV2.InvalidTier.selector);
        staking.setTier(3, 1e18, 10);
    }

    function test_setTier_revertsMaxSlotsBelowUsed() public {
        // Stake to use 1 slot
        vm.prank(user1);
        staking.stake(0);

        // Try to set maxSlots to 0
        vm.prank(owner);
        vm.expectRevert("maxSlots < usedSlots");
        staking.setTier(0, TIER0_AMOUNT, 0);
    }

    function test_setTier_revertsNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.setTier(0, 1e18, 10);
    }

    // ═══════════════════════════════════════════════════════
    //                    YIELD MATH TESTS
    // ═══════════════════════════════════════════════════════

    function test_yieldMath_tier0() public view {
        uint256 yieldAmount = (TIER0_AMOUNT * 500) / 10_000;
        assertEq(yieldAmount, 651_500e18); // 5% of 13,030,000
    }

    function test_yieldMath_tier1() public view {
        uint256 yieldAmount = (TIER1_AMOUNT * 500) / 10_000;
        assertEq(yieldAmount, 1_251_500e18); // 5% of 25,030,000
    }

    function test_yieldMath_tier2() public view {
        uint256 yieldAmount = (TIER2_AMOUNT * 500) / 10_000;
        assertEq(yieldAmount, 6_501_500e18); // 5% of 130,030,000
    }

    // ═══════════════════════════════════════════════════════
    //                     VIEW TESTS
    // ═══════════════════════════════════════════════════════

    function test_getStakeCount_zero() public view {
        assertEq(staking.getStakeCount(user1), 0);
    }

    function test_getStakes_empty() public view {
        CLAWDStakeV2.StakeInfo[] memory s = staking.getStakes(user1);
        assertEq(s.length, 0);
    }

    // ═══════════════════════════════════════════════════════
    //                   INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════

    function test_fullLifecycle() public {
        // User stakes in tier 0
        vm.prank(user1);
        staking.stake(0);

        // Wait lock period
        vm.warp(block.timestamp + 180 days + 1);

        // Track balances
        uint256 userBalBefore = token.balanceOf(user1);
        uint256 reserveBefore = staking.houseReserve();

        // Unstake
        vm.prank(user1);
        staking.unstake(0);

        uint256 userBalAfter = token.balanceOf(user1);
        uint256 reserveAfter = staking.houseReserve();

        uint256 yieldAmount = (TIER0_AMOUNT * 500) / 10_000;
        uint256 burnAmount = (TIER0_AMOUNT * 500) / 10_000;

        // User got principal + yield
        assertEq(userBalAfter - userBalBefore, TIER0_AMOUNT + yieldAmount);
        // House reserve decreased by yield + burn
        assertEq(reserveBefore - reserveAfter, yieldAmount + burnAmount);
        // No stakes remaining
        assertEq(staking.getStakeCount(user1), 0);
    }

    function test_multipleUsersStakeAndUnstake() public {
        vm.prank(user1);
        staking.stake(0);

        vm.prank(user2);
        staking.stake(1);

        vm.warp(block.timestamp + 180 days + 1);

        vm.prank(user1);
        staking.unstake(0);

        vm.prank(user2);
        staking.unstake(0);

        assertEq(staking.getStakeCount(user1), 0);
        assertEq(staking.getStakeCount(user2), 0);
    }
}
