"use client";

import { useState, useCallback } from "react";
import { useAccount, useChainId, useSwitchChain, useReadContract } from "wagmi";
import { base } from "viem/chains";
import type { NextPage } from "next";
import { formatEther } from "viem";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";
import deployedContracts from "~~/contracts/deployedContracts";

const TIER_NAMES = ["🥉 Bronze", "🥈 Silver", "🥇 Gold"];
const LOCK_DAYS = 180;
const YIELD_PCT = 5;
const BASE_CHAIN_ID = base.id;

const CONTRACT_ADDRESS = (deployedContracts as any)[BASE_CHAIN_ID]?.CLAWDStakeV2?.address || "0x8410d83faf78313967160b7a45d315cbe66380b2";

const Home: NextPage = () => {
  const { address: connectedAddress, isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain, isPending: isSwitchingChain } = useSwitchChain();

  const isWrongNetwork = isConnected && chainId !== BASE_CHAIN_ID;

  // ── Read tiers ──
  const { data: tier0 } = useScaffoldReadContract({ contractName: "CLAWDStakeV2", functionName: "getTier", args: [0] });
  const { data: tier1 } = useScaffoldReadContract({ contractName: "CLAWDStakeV2", functionName: "getTier", args: [1] });
  const { data: tier2 } = useScaffoldReadContract({ contractName: "CLAWDStakeV2", functionName: "getTier", args: [2] });
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

  // ── Read CLAWD allowance (ERC20 token) ──
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: "0x9F86d2b6FC636C93727614d7e3D959c9dAeDEa67",
    functionName: "allowance",
    args: [connectedAddress!, CONTRACT_ADDRESS],
    query: { enabled: !!connectedAddress },
  });

  // ── Write contracts ──
  const { writeContractAsync: stakeWrite, isMining: isStakingTx } = useScaffoldWriteContract({ contractName: "CLAWDStakeV2" });
  const { writeContractAsync: unstakeWrite, isMining: isUnstakingTx } = useScaffoldWriteContract({ contractName: "CLAWDStakeV2" });
  const { writeContractAsync: approveWrite, isMining: isApprovingTx } = useScaffoldWriteContract({ contractName: "CLAWDStakeV2" });

  // ── Error state ──
  const [error, setError] = useState<string | null>(null);

  // ── Pending state for multi-step flow ──
  const [pendingTier, setPendingTier] = useState<number | null>(null);

  const formatCLAWD = (amount: bigint | undefined) => {
    if (!amount) return "0";
    const num = Number(formatEther(amount));
    return num.toLocaleString("en-US", { maximumFractionDigits: 0 });
  };

  const parseError = (e: unknown): string => {
    if (typeof e === "object" && e !== null) {
      const err = e as Record<string, unknown>;
      if (err.message && typeof err.message === "string") {
        if (err.message.includes("User rejected")) return "Transaction rejected in wallet.";
        if (err.message.includes("insufficient funds")) return "Insufficient gas.";
        return err.message.slice(0, 120);
      }
    }
    return "Transaction failed. Please try again.";
  };

  const handleSwitchNetwork = useCallback(() => {
    switchChain?.({ chainId: BASE_CHAIN_ID });
  }, [switchChain]);

  const handleApprove = async (tierIndex: number, amount: bigint) => {
    setError(null);
    setPendingTier(tierIndex);
    try {
      await approveWrite({
        functionName: "approve",
        args: [CONTRACT_ADDRESS, amount],
      });
      refetchAllowance();
    } catch (e) {
      setError(parseError(e));
    } finally {
      setPendingTier(null);
    }
  };

  const handleStake = async (tierIndex: number) => {
    setError(null);
    setPendingTier(tierIndex);
    try {
      await stakeWrite({ functionName: "stake", args: [tierIndex] });
      refetchStakes();
    } catch (e) {
      setError(parseError(e));
    } finally {
      setPendingTier(null);
    }
  };

  const handleUnstake = async (stakeIndex: number) => {
    setError(null);
    try {
      await unstakeWrite({ functionName: "unstake", args: [BigInt(stakeIndex)] });
      refetchStakes();
    } catch (e) {
      setError(parseError(e));
    }
  };

  const getUnlockDate = (stakedAt: bigint) => new Date((Number(stakedAt) + LOCK_DAYS * 86400) * 1000);
  const isUnlocked = (stakedAt: bigint) => Date.now() / 1000 >= Number(stakedAt) + LOCK_DAYS * 86400;
  const getDaysRemaining = (stakedAt: bigint) => Math.max(0, Math.ceil((Number(stakedAt) + LOCK_DAYS * 86400 - Date.now() / 1000) / 86400));

  // ── Compute approval status ──
  const maxTierAmount = tier2?.stakeAmount ?? 130030000n * 10n ** 18n;
  const needsApproval = isConnected && !isWrongNetwork && !!connectedAddress && (allowance === undefined || allowance < maxTierAmount);
  const isApprovePending = isApprovingTx && pendingTier !== null;

  return (
    <div className="flex flex-col items-center grow pt-8 px-4">
      {/* Header */}
      <div className="text-center mb-8">
        <h1 className="text-5xl font-bold mb-2">🐾 CLAWD Stake V2</h1>
        <p className="text-lg opacity-70">
          Lock your CLAWD tokens · Earn {YIELD_PCT}% yield · {LOCK_DAYS}-day lock
        </p>
        {houseReserve !== undefined && (
          <p className="text-sm mt-2 opacity-50">
            House Reserve: {formatCLAWD(houseReserve)} CLAWD
          </p>
        )}
      </div>

      {/* Error banner */}
      {error && (
        <div className="alert alert-error mb-6 max-w-5xl w-full">
          <span>{error}</span>
          <button className="btn btn-ghost btn-sm" onClick={() => setError(null)}>✕</button>
        </div>
      )}

      {/* Tier Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 w-full max-w-5xl mb-12">
        {tiers.map((tier, i) => {
          const stakeAmount = tier?.stakeAmount ?? 0n;
          const maxSlots = tier?.maxSlots ?? 0;
          const usedSlots = Number(tier?.usedSlots ?? 0);
          const availableSlots = maxSlots - usedSlots;
          const yieldAmount = (stakeAmount * BigInt(YIELD_PCT)) / 100n;

          // 4-state button logic
          const isLoading = (isStakingTx || isApprovingTx) && pendingTier === i;
          const disabled = !isConnected || availableSlots === 0 || isLoading;

          let button: React.ReactNode = null;
          if (!isConnected) {
            button = <span className="btn btn-primary btn-wide mt-4 opacity-50">Connect wallet to stake</span>;
          } else if (isWrongNetwork) {
            button = (
              <button className="btn btn-secondary btn-wide mt-4" onClick={handleSwitchNetwork} disabled={isSwitchingChain}>
                {isSwitchingChain ? <span className="loading loading-spinner loading-sm" /> : null}
                {isSwitchingChain ? "Switching..." : "Switch to Base"}
              </button>
            );
          } else if (needsApproval) {
            button = (
              <button
                className="btn btn-accent btn-wide mt-4"
                disabled={disabled || isApprovePending}
                onClick={() => handleApprove(i, maxTierAmount)}
              >
                {isApprovePending ? <span className="loading loading-spinner loading-sm" /> : null}
                {isApprovePending ? "Approving..." : "Approve CLAWD"}
              </button>
            );
          } else {
            button = (
              <button
                className="btn btn-primary btn-wide mt-4"
                disabled={disabled || isStakingTx}
                onClick={() => handleStake(i)}
              >
                {isStakingTx ? <span className="loading loading-spinner loading-sm" /> : null}
                {isStakingTx ? "Staking..." : "Stake"}
              </button>
            );
          }

          return (
            <div key={i} className="card bg-base-100 shadow-xl border border-base-300 hover:border-primary transition-all">
              <div className="card-body items-center text-center">
                <h2 className="card-title text-2xl">{TIER_NAMES[i]}</h2>
                <div className="divider my-1" />

                <div className="stat px-0">
                  <div className="stat-title">Stake Amount</div>
                  <div className="stat-value text-lg">{formatCLAWD(stakeAmount)} CLAWD</div>
                </div>
                <div className="stat px-0">
                  <div className="stat-title">Yield ({YIELD_PCT}%)</div>
                  <div className="stat-value text-lg text-success">+{formatCLAWD(yieldAmount)} CLAWD</div>
                </div>
                <div className="stat px-0">
                  <div className="stat-title">Available Slots</div>
                  <div className="stat-value text-lg">
                    <span className={availableSlots === 0 ? "text-error" : ""}>{availableSlots} / {maxSlots}</span>
                  </div>
                </div>
                <div className="stat px-0">
                  <div className="stat-title">Lock Period</div>
                  <div className="stat-value text-lg">{LOCK_DAYS} days</div>
                </div>

                {button}

                {needsApproval && !isWrongNetwork && (
                  <p className="text-xs opacity-50 mt-2">Approval required before staking</p>
                )}
                {availableSlots === 0 && (
                  <p className="text-xs text-error mt-2">All slots full</p>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* User Stakes */}
      {isConnected && !isWrongNetwork && (
        <div className="w-full max-w-5xl mb-12">
          <h2 className="text-3xl font-bold text-center mb-6">Your Stakes</h2>
          {(!userStakes || userStakes.length === 0) ? (
            <div className="text-center opacity-50 py-8">
              <p className="text-xl">No active stakes</p>
              <p>Choose a tier above to start earning</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="table table-zebra w-full">
                <thead>
                  <tr>
                    <th>#</th><th>Tier</th><th>Staked</th><th>Yield</th>
                    <th>Unlock Date</th><th>Status</th><th>Action</th>
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
                        <td className="text-success">+{formatCLAWD(yieldAmt)} CLAWD</td>
                        <td>{getUnlockDate(stake.stakedAt).toLocaleDateString()}</td>
                        <td>
                          {unlocked
                            ? <span className="badge badge-success">Unlocked</span>
                            : <span className="badge badge-warning">{daysLeft} days left</span>
                          }
                        </td>
                        <td>
                          <button
                            className="btn btn-sm btn-outline btn-success"
                            disabled={!unlocked || isUnstakingTx}
                            onClick={() => handleUnstake(idx)}
                          >
                            {isUnstakingTx ? <span className="loading loading-spinner loading-xs" /> : null}
                            {isUnstakingTx ? "Unstaking..." : unlocked ? "Unstake" : "Locked"}
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
          <li><strong>Choose a tier</strong> — Bronze (13M), Silver (25M), or Gold (130M) CLAWD</li>
          <li><strong>Approve & stake</strong> — Your tokens are locked for {LOCK_DAYS} days</li>
          <li><strong>Wait</strong> — Your tokens are safely locked in the contract</li>
          <li><strong>Unstake</strong> — After {LOCK_DAYS} days, claim principal + {YIELD_PCT}% yield</li>
          <li><strong>Burn</strong> — {YIELD_PCT}% of stake amount is burned from house reserve</li>
        </ol>
        <div className="mt-4 p-4 bg-base-300 rounded-xl">
          <p className="text-sm opacity-70">
            <strong>Contract:</strong>{" "}
            <a
              href={`https://basescan.org/address/${CONTRACT_ADDRESS}`}
              target="_blank"
              rel="noopener noreferrer"
              className="link link-primary font-mono text-xs"
            >
              {CONTRACT_ADDRESS}
            </a>{" "}
            on Base
          </p>
        </div>
      </div>
    </div>
  );
};

export default Home;
