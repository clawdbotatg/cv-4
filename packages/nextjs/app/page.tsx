"use client";

import { useState, useEffect } from "react";
import { useAccount } from "wagmi";
import type { NextPage } from "next";
import { formatEther, parseEther } from "viem";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

const TIER_NAMES = ["🥉 Bronze", "🥈 Silver", "🥇 Gold"];
const LOCK_DAYS = 180;
const YIELD_PCT = 5;

const Home: NextPage = () => {
  const { address: connectedAddress } = useAccount();

  // ── Read tiers ──
  const { data: tier0 } = useScaffoldReadContract({
    contractName: "CLAWDStakeV2",
    functionName: "getTier",
    args: [0],
  });
  const { data: tier1 } = useScaffoldReadContract({
    contractName: "CLAWDStakeV2",
    functionName: "getTier",
    args: [1],
  });
  const { data: tier2 } = useScaffoldReadContract({
    contractName: "CLAWDStakeV2",
    functionName: "getTier",
    args: [2],
  });

  const tiers = [tier0, tier1, tier2];

  // ── Read user stakes ──
  const { data: userStakes, refetch: refetchStakes } = useScaffoldReadContract({
    contractName: "CLAWDStakeV2",
    functionName: "getStakes",
    args: [connectedAddress],
  });

  // ── Read house reserve ──
  const { data: houseReserve } = useScaffoldReadContract({
    contractName: "CLAWDStakeV2",
    functionName: "houseReserve",
  });

  // ── Write: stake ──
  const { writeContractAsync: stakeWrite } = useScaffoldWriteContract({
    contractName: "CLAWDStakeV2",
  });

  // ── Write: unstake ──
  const { writeContractAsync: unstakeWrite } = useScaffoldWriteContract({
    contractName: "CLAWDStakeV2",
  });

  const [isStaking, setIsStaking] = useState(false);
  const [isUnstaking, setIsUnstaking] = useState<number | null>(null);

  const handleStake = async (tierIndex: number) => {
    setIsStaking(true);
    try {
      await stakeWrite({
        functionName: "stake",
        args: [tierIndex],
      });
      refetchStakes();
    } catch (e) {
      console.error("Stake error:", e);
    }
    setIsStaking(false);
  };

  const handleUnstake = async (stakeIndex: number) => {
    setIsUnstaking(stakeIndex);
    try {
      await unstakeWrite({
        functionName: "unstake",
        args: [BigInt(stakeIndex)],
      });
      refetchStakes();
    } catch (e) {
      console.error("Unstake error:", e);
    }
    setIsUnstaking(null);
  };

  const formatCLAWD = (amount: bigint | undefined) => {
    if (!amount) return "0";
    const num = Number(formatEther(amount));
    return num.toLocaleString("en-US", { maximumFractionDigits: 0 });
  };

  const getUnlockDate = (stakedAt: bigint) => {
    const unlockTs = Number(stakedAt) + LOCK_DAYS * 86400;
    return new Date(unlockTs * 1000);
  };

  const isUnlocked = (stakedAt: bigint) => {
    const unlockTs = Number(stakedAt) + LOCK_DAYS * 86400;
    return Date.now() / 1000 >= unlockTs;
  };

  const getDaysRemaining = (stakedAt: bigint) => {
    const unlockTs = Number(stakedAt) + LOCK_DAYS * 86400;
    const remaining = unlockTs - Date.now() / 1000;
    if (remaining <= 0) return 0;
    return Math.ceil(remaining / 86400);
  };

  return (
    <div className="flex flex-col items-center grow pt-8 px-4">
      {/* Header */}
      <div className="text-center mb-8">
        <h1 className="text-5xl font-bold mb-2">🐾 CLAWD Stake V2</h1>
        <p className="text-lg opacity-70">
          Lock your CLAWD tokens • Earn {YIELD_PCT}% yield • {LOCK_DAYS}-day lock
        </p>
        {houseReserve !== undefined && (
          <p className="text-sm mt-2 opacity-50">
            House Reserve: {formatCLAWD(houseReserve)} CLAWD
          </p>
        )}
      </div>

      {/* Tier Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 w-full max-w-5xl mb-12">
        {tiers.map((tier, i) => {
          const stakeAmount = tier?.stakeAmount;
          const maxSlots = tier?.maxSlots;
          const usedSlots = tier?.usedSlots;
          const availableSlots = maxSlots !== undefined && usedSlots !== undefined
            ? Number(maxSlots) - Number(usedSlots)
            : undefined;
          const yieldAmount = stakeAmount ? (stakeAmount * BigInt(YIELD_PCT)) / 100n : 0n;

          return (
            <div
              key={i}
              className="card bg-base-100 shadow-xl border border-base-300 hover:border-primary transition-all"
            >
              <div className="card-body items-center text-center">
                <h2 className="card-title text-2xl">{TIER_NAMES[i]}</h2>

                <div className="divider my-1" />

                <div className="stat px-0">
                  <div className="stat-title">Stake Amount</div>
                  <div className="stat-value text-lg">
                    {formatCLAWD(stakeAmount)} CLAWD
                  </div>
                </div>

                <div className="stat px-0">
                  <div className="stat-title">Yield ({YIELD_PCT}%)</div>
                  <div className="stat-value text-lg text-success">
                    +{formatCLAWD(yieldAmount)} CLAWD
                  </div>
                </div>

                <div className="stat px-0">
                  <div className="stat-title">Available Slots</div>
                  <div className="stat-value text-lg">
                    {availableSlots !== undefined ? (
                      <span className={availableSlots === 0 ? "text-error" : ""}>
                        {availableSlots} / {Number(maxSlots)}
                      </span>
                    ) : (
                      "..."
                    )}
                  </div>
                </div>

                <div className="stat px-0">
                  <div className="stat-title">Lock Period</div>
                  <div className="stat-value text-lg">{LOCK_DAYS} days</div>
                </div>

                <button
                  className="btn btn-primary btn-wide mt-4"
                  disabled={!connectedAddress || isStaking || availableSlots === 0}
                  onClick={() => handleStake(i)}
                >
                  {isStaking ? (
                    <span className="loading loading-spinner loading-sm" />
                  ) : availableSlots === 0 ? (
                    "Tier Full"
                  ) : (
                    "Stake"
                  )}
                </button>

                <p className="text-xs opacity-50 mt-2">
                  Requires CLAWD token approval first
                </p>
              </div>
            </div>
          );
        })}
      </div>

      {/* User Stakes */}
      {connectedAddress && (
        <div className="w-full max-w-5xl mb-12">
          <h2 className="text-3xl font-bold text-center mb-6">Your Stakes</h2>

          {(!userStakes || userStakes.length === 0) ? (
            <div className="text-center opacity-50 py-8">
              <p className="text-xl">No active stakes</p>
              <p>Choose a tier above to start staking</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Tier</th>
                    <th>Staked</th>
                    <th>Yield</th>
                    <th>Unlock Date</th>
                    <th>Status</th>
                    <th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {userStakes.map((stake, idx) => {
                    const unlocked = isUnlocked(stake.stakedAt);
                    const daysLeft = getDaysRemaining(stake.stakedAt);
                    const yieldAmt = (stake.stakeAmount * BigInt(YIELD_PCT)) / 100n;

                    return (
                      <tr key={idx}>
                        <td>{idx}</td>
                        <td>{TIER_NAMES[stake.tierIndex]}</td>
                        <td>{formatCLAWD(stake.stakeAmount)} CLAWD</td>
                        <td className="text-success">
                          +{formatCLAWD(yieldAmt)} CLAWD
                        </td>
                        <td>{getUnlockDate(stake.stakedAt).toLocaleDateString()}</td>
                        <td>
                          {unlocked ? (
                            <span className="badge badge-success">Unlocked</span>
                          ) : (
                            <span className="badge badge-warning">
                              {daysLeft} days left
                            </span>
                          )}
                        </td>
                        <td>
                          <button
                            className="btn btn-sm btn-outline btn-success"
                            disabled={!unlocked || isUnstaking === idx}
                            onClick={() => handleUnstake(idx)}
                          >
                            {isUnstaking === idx ? (
                              <span className="loading loading-spinner loading-xs" />
                            ) : unlocked ? (
                              "Unstake"
                            ) : (
                              "Locked"
                            )}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* Info Section */}
      <div className="w-full max-w-3xl mb-12 bg-base-200 rounded-2xl p-8">
        <h3 className="text-2xl font-bold mb-4">How It Works</h3>
        <ol className="list-decimal list-inside space-y-2 opacity-80">
          <li>
            <strong>Choose a tier</strong> — Bronze (13M), Silver (25M), or Gold (130M) CLAWD
          </li>
          <li>
            <strong>Approve & stake</strong> — Your tokens are locked for {LOCK_DAYS} days
          </li>
          <li>
            <strong>Wait</strong> — Your tokens are safely locked in the contract
          </li>
          <li>
            <strong>Unstake</strong> — After {LOCK_DAYS} days, claim your principal + {YIELD_PCT}% yield
          </li>
          <li>
            <strong>Burn</strong> — {YIELD_PCT}% of your stake amount is burned from the house reserve
          </li>
        </ol>
        <div className="mt-4 p-4 bg-base-300 rounded-xl">
          <p className="text-sm opacity-70">
            <strong>Contract:</strong>{" "}
            <a
              href="https://basescan.org/address/0x8410d83faf78313967160b7a45d315cbe66380b2"
              target="_blank"
              rel="noopener noreferrer"
              className="link link-primary"
            >
              0x8410...80b2
            </a>{" "}
            on Base
          </p>
        </div>
      </div>
    </div>
  );
};

export default Home;
