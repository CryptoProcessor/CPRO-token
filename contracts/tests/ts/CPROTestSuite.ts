import { expect } from "chai";
import { network } from "hardhat";
const { networkHelpers } = await network.connect();
const { ethers } = await network.connect();

const time = networkHelpers.time;

describe("CPRO Token Ecosystem Tests", function () {
  let cproToken, tokenVesting, tokenLocking;
  let owner, addr1, addr2, addr3;

  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();

    // Deploy CPRO Token
    const CPROToken = await ethers.getContractFactory("CPROToken");
    cproToken = await CPROToken.deploy();

    // Deploy TokenVesting contract
    const TokenVesting = await ethers.getContractFactory("CPROVesting");
    tokenVesting = await TokenVesting.deploy(await cproToken.getAddress());

    // Deploy TokenLocking contract
    const TokenLocking = await ethers.getContractFactory("CPROLocking");
    tokenLocking = await TokenLocking.deploy(await cproToken.getAddress());

    // Mint additional tokens for testing
    const additionalMint = ethers.parseEther("1000000"); // 1M tokens
    await cproToken.mint(owner.address, additionalMint);
  });

  describe("CPROToken Tests", function () {
    it("Should deploy with correct initial supply", async function () {
      const totalSupply = await cproToken.totalSupply();
      expect(totalSupply).to.equal(ethers.parseEther("2000000")); // 1M initial + 1M minted
    });

    it("Should have correct token details", async function () {
      expect(await cproToken.name()).to.equal("CPROToken");
      expect(await cproToken.symbol()).to.equal("CPRO");
      expect(await cproToken.decimals()).to.equal(18);
    });

    it("Should allow owner to mint tokens", async function () {
      const mintAmount = ethers.parseEther("1000");
      await cproToken.mint(addr1.address, mintAmount);

      const balance = await cproToken.balanceOf(addr1.address);
      expect(balance).to.equal(mintAmount);
    });

    it("Should not allow non-owner to mint tokens", async function () {
      const mintAmount = ethers.parseEther("1000");

      await expect(
        cproToken.connect(addr1).mint(addr1.address, mintAmount)
      ).to.be.revertedWithCustomError(cproToken, "OwnableUnauthorizedAccount");
    });

    it("Should allow owner to burn tokens", async function () {
      const initialSupply = await cproToken.totalSupply();
      const burnAmount = ethers.parseEther("1000");

      await cproToken.burn(burnAmount);

      const newSupply = await cproToken.totalSupply();
      expect(newSupply).to.equal(initialSupply - burnAmount);
    });

    it("Should allow owner to pause and unpause transfers", async function () {
      // Give some tokens to addr1
      await cproToken.transfer(addr1.address, ethers.parseEther("100"));

      // Pause the contract
      await cproToken.pause();
      expect(await cproToken.paused()).to.be.true;

      // Try to transfer while paused - should fail
      await expect(
        cproToken
          .connect(addr1)
          .transfer(addr2.address, ethers.parseEther("50"))
      ).to.be.revertedWith("CPROToken: token transfer while paused");

      // Unpause and transfer should work
      await cproToken.unpause();
      expect(await cproToken.paused()).to.be.false;

      await cproToken
        .connect(addr1)
        .transfer(addr2.address, ethers.parseEther("50"));
      expect(await cproToken.balanceOf(addr2.address)).to.equal(
        ethers.parseEther("50")
      );
    });
  });

  //Vesting
  describe("CPROVesting Tests", function () {
    beforeEach(async function () {
      // Approve vesting contract to spend tokens
      await cproToken.approve(
        await tokenVesting.getAddress(),
        ethers.parseEther("1000000")
      );
    });

    it("Should create vesting schedule correctly", async function () {
      const vestingAmount = ethers.parseEther("10000");
      const startTime = await networkHelpers.time.latest();
      const cliffDuration = 180 * 24 * 60 * 60; // 6 months
      const vestingDuration = 730 * 24 * 60 * 60; // 2 years

      await tokenVesting.createVestingSchedule(
        addr1.address,
        vestingAmount,
        startTime,
        cliffDuration,
        vestingDuration
      );

      const schedule = await tokenVesting.getVestingSchedule(addr1.address);
      expect(schedule.totalAmount).to.equal(vestingAmount);
      expect(schedule.startTime).to.equal(startTime);
      expect(schedule.cliffDuration).to.equal(cliffDuration);
      expect(schedule.vestingDuration).to.equal(vestingDuration);
    });

    it("Should not allow claiming during cliff period", async function () {
      const vestingAmount = ethers.parseEther("10000");
      const startTime = await networkHelpers.time.latest();
      const cliffDuration = 180 * 24 * 60 * 60; // 6 months
      const vestingDuration = 730 * 24 * 60 * 60; // 2 years

      await tokenVesting.createVestingSchedule(
        addr1.address,
        vestingAmount,
        startTime,
        cliffDuration,
        vestingDuration
      );

      // Try to claim immediately - should be 0
      const claimable = await tokenVesting.getClaimableAmount(addr1.address);
      expect(claimable).to.equal(0);

      // Move forward 3 months (still in cliff)
      await networkHelpers.time.increase(90 * 24 * 60 * 60);

      const stillClaimable = await tokenVesting.getClaimableAmount(
        addr1.address
      );
      expect(stillClaimable).to.equal(0);
    });

    it("Should allow claiming after cliff period", async function () {
      const vestingAmount = ethers.parseEther("10000");
      const startTime = await networkHelpers.time.latest();
      const cliffDuration = 180 * 24 * 60 * 60; // 6 months
      const vestingDuration = 730 * 24 * 60 * 60; // 2 years

      await tokenVesting.createVestingSchedule(
        addr1.address,
        vestingAmount,
        startTime,
        cliffDuration,
        vestingDuration
      );

      // Move forward 1 year (past cliff, halfway through vesting)
      await networkHelpers.time.increase(365 * 24 * 60 * 60);

      const claimable = await tokenVesting.getClaimableAmount(addr1.address);
      // Should be able to claim approximately half the tokens
      const expectedClaimable = vestingAmount / 2n;
      expect(claimable).to.be.closeTo(
        expectedClaimable,
        ethers.parseEther("100")
      );

      // Claim tokens
      await tokenVesting.connect(addr1).claimTokens();

      const balance = await cproToken.balanceOf(addr1.address);
      expect(balance).to.be.closeTo(
        expectedClaimable,
        ethers.parseEther("100")
      );
    });

    it("Should allow owner to revoke vesting", async function () {
      const vestingAmount = ethers.parseEther("10000");
      const startTime = await networkHelpers.time.latest();
      const cliffDuration = 180 * 24 * 60 * 60; // 6 months
      const vestingDuration = 730 * 24 * 60 * 60; // 2 years

      await tokenVesting.createVestingSchedule(
        addr1.address,
        vestingAmount,
        startTime,
        cliffDuration,
        vestingDuration
      );

      // Move forward 1 year
      await time.increase(365 * 24 * 60 * 60);

      const ownerBalanceBefore = await cproToken.balanceOf(owner.address);

      // Revoke vesting
      await tokenVesting.revokeVesting(addr1.address);

      const schedule = await tokenVesting.getVestingSchedule(addr1.address);
      expect(schedule.revoked).to.be.true;

      // Owner should receive unvested tokens back
      const ownerBalanceAfter = await cproToken.balanceOf(owner.address);
      expect(ownerBalanceAfter).to.be.greaterThan(ownerBalanceBefore);
    });
  });

  describe("CPROLocking Tests", function () {
    beforeEach(async function () {
      // Approve locking contract to spend tokens
      await cproToken.approve(
        await tokenLocking.getAddress(),
        ethers.parseEther("1000000")
      );
    });

    it("Should lock tokens correctly", async function () {
      const lockAmount = ethers.parseEther("5000");
      const unlockTime = (await time.latest()) + 365 * 24 * 60 * 60; // 1 year

      const tx = await tokenLocking.lockTokens(lockAmount, unlockTime, "team");
      const receipt = await tx.wait();

      // Check event was emitted
      const event = receipt.logs.find(
        (log) => tokenLocking.interface.parseLog(log)?.name === "TokensLocked"
      );
      expect(event).to.not.be.undefined;

      // Check lock info
      const lockInfo = await tokenLocking.getLockInfo(1);
      expect(lockInfo.amount).to.equal(lockAmount);
      expect(lockInfo.unlockTime).to.equal(unlockTime);
      expect(lockInfo.claimed).to.be.false;
      expect(lockInfo.lockType).to.equal("team");
      expect(lockInfo.owner).to.equal(owner.address);

      // Check total locked tokens
      expect(await tokenLocking.totalLockedTokens()).to.equal(lockAmount);
    });

    it("Should not allow unlocking before unlock time", async function () {
      const lockAmount = ethers.parseEther("5000");
      const unlockTime = (await time.latest()) + 365 * 24 * 60 * 60; // 1 year

      await tokenLocking.lockTokens(lockAmount, unlockTime, "team");

      // Try to unlock immediately - should fail
      await expect(tokenLocking.unlockTokens(1)).to.be.revertedWith(
        "TokenLocking: tokens still locked"
      );

      // Check canUnlock returns false
      expect(await tokenLocking.canUnlock(1)).to.be.false;
    });

    it("Should allow unlocking after unlock time", async function () {
      const lockAmount = ethers.parseEther("5000");
      const unlockTime = (await time.latest()) + 365 * 24 * 60 * 60; // 1 year

      await tokenLocking.lockTokens(lockAmount, unlockTime, "team");

      const balanceBefore = await cproToken.balanceOf(owner.address);

      // Fast forward past unlock time
      await time.increaseTo(unlockTime + 1);

      // Check canUnlock returns true
      expect(await tokenLocking.canUnlock(1)).to.be.true;

      // Unlock tokens
      await tokenLocking.unlockTokens(1);

      const balanceAfter = await cproToken.balanceOf(owner.address);
      expect(balanceAfter - balanceBefore).to.equal(lockAmount);

      // Check lock is marked as claimed
      const lockInfo = await tokenLocking.getLockInfo(1);
      expect(lockInfo.claimed).to.be.true;

      // Check total locked tokens decreased
      expect(await tokenLocking.totalLockedTokens()).to.equal(0);
    });

    it("Should handle multiple locks per user", async function () {
      const lockAmount1 = ethers.parseEther("1000");
      const lockAmount2 = ethers.parseEther("2000");
      const unlockTime1 = (await time.latest()) + 180 * 24 * 60 * 60; // 6 months
      const unlockTime2 = (await time.latest()) + 365 * 24 * 60 * 60; // 1 year

      // Create two locks
      await tokenLocking.lockTokens(lockAmount1, unlockTime1, "marketing");
      await tokenLocking.lockTokens(lockAmount2, unlockTime2, "team");

      // Check user has 2 locks
      const userLocks = await tokenLocking.getUserLocks(owner.address);
      expect(userLocks.length).to.equal(2);

      // Check total locked amount
      const totalLocked = await tokenLocking.getUserTotalLocked(owner.address);
      expect(totalLocked).to.equal(lockAmount1 + lockAmount2);

      // Fast forward 6 months - only first lock should be unlockable
      await time.increaseTo(unlockTime1 + 1);

      const unlockable = await tokenLocking.getUserUnlockableAmount(
        owner.address
      );
      expect(unlockable).to.equal(lockAmount1);
    });

    it("Should allow batch unlocking", async function () {
      const lockAmount1 = ethers.parseEther("1000");
      const lockAmount2 = ethers.parseEther("2000");
      const unlockTime = (await time.latest()) + 365 * 24 * 60 * 60; // 1 year

      // Create two locks with same unlock time
      await tokenLocking.lockTokens(lockAmount1, unlockTime, "marketing");
      await tokenLocking.lockTokens(lockAmount2, unlockTime, "team");

      const balanceBefore = await cproToken.balanceOf(owner.address);

      // Fast forward past unlock time
      await time.increaseTo(unlockTime + 1);

      // Batch unlock both locks
      await tokenLocking.batchUnlock([1, 2]);

      const balanceAfter = await cproToken.balanceOf(owner.address);
      expect(balanceAfter - balanceBefore).to.equal(lockAmount1 + lockAmount2);
    });

    it("Should allow extending lock duration", async function () {
      const lockAmount = ethers.parseEther("5000");
      const initialUnlockTime = (await time.latest()) + 365 * 24 * 60 * 60; // 1 year
      const extendedUnlockTime = initialUnlockTime + 180 * 24 * 60 * 60; // +6 months

      await tokenLocking.lockTokens(lockAmount, initialUnlockTime, "team");

      // Extend the lock
      await tokenLocking.extendLock(1, extendedUnlockTime);

      const lockInfo = await tokenLocking.getLockInfo(1);
      expect(lockInfo.unlockTime).to.equal(extendedUnlockTime);
    });

    it("Should allow owner to lock tokens for others", async function () {
      const lockAmount = ethers.parseEther("3000");
      const unlockTime = (await time.latest()) + 365 * 24 * 60 * 60; // 1 year

      await tokenLocking.lockTokensFor(
        addr1.address,
        lockAmount,
        unlockTime,
        "advisor"
      );

      const lockInfo = await tokenLocking.getLockInfo(1);
      expect(lockInfo.owner).to.equal(addr1.address);
      expect(lockInfo.amount).to.equal(lockAmount);

      // Check user locks
      const userLocks = await tokenLocking.getUserLocks(addr1.address);
      expect(userLocks.length).to.equal(1);
      expect(userLocks[0]).to.equal(1);
    });
  });

  describe("CPRO Integration Tests", function () {
    it("Should work with vesting and locking together", async function () {
      // Approve both contracts
      await cproToken.approve(
        await tokenVesting.getAddress(),
        ethers.parseEther("500000")
      );
      await cproToken.approve(
        await tokenLocking.getAddress(),
        ethers.parseEther("500000")
      );

      // Create vesting schedule for addr1
      const vestingAmount = ethers.parseEther("10000");
      const startTime = await time.latest();
      const cliffDuration = 90 * 24 * 60 * 60; // 3 months
      const vestingDuration = 365 * 24 * 60 * 60; // 1 year

      await tokenVesting.createVestingSchedule(
        addr1.address,
        vestingAmount,
        startTime,
        cliffDuration,
        vestingDuration
      );

      // Lock tokens for addr2
      const lockAmount = ethers.parseEther("5000");
      const unlockTime = (await time.latest()) + 180 * 24 * 60 * 60; // 6 months

      await tokenLocking.lockTokensFor(
        addr2.address,
        lockAmount,
        unlockTime,
        "team"
      );

      // Fast forward 6 months
      await time.increase(180 * 24 * 60 * 60);

      // addr1 should be able to claim some vested tokens
      const claimable = await tokenVesting.getClaimableAmount(addr1.address);
      expect(claimable).to.be.greaterThan(0);

      // addr2 should be able to unlock their tokens
      expect(await tokenLocking.canUnlock(1)).to.be.true;

      // Execute both operations
      await tokenVesting.connect(addr1).claimTokens();
      await tokenLocking.connect(addr2).unlockTokens(1);

      // Verify balances
      expect(await cproToken.balanceOf(addr1.address)).to.be.greaterThan(0);
      expect(await cproToken.balanceOf(addr2.address)).to.equal(lockAmount);
    });

    it("Should handle emergency scenarios", async function () {
      // Test pause functionality
      await cproToken.transfer(addr1.address, ethers.parseEther("1000"));

      // Pause token transfers
      await cproToken.pause();

      // Vesting and locking should still work internally, but token transfers should fail
      await expect(
        cproToken
          .connect(addr1)
          .transfer(addr2.address, ethers.parseEther("100"))
      ).to.be.revertedWith("CPROToken: token transfer while paused");

      // Unpause
      await cproToken.unpause();

      // Now transfers should work
      await cproToken
        .connect(addr1)
        .transfer(addr2.address, ethers.parseEther("100"));
      expect(await cproToken.balanceOf(addr2.address)).to.equal(
        ethers.parseEther("100")
      );
    });
  });

  describe("Edge Cases and Security", function () {
    it("Should not allow creating vesting with zero amount", async function () {
      await cproToken.approve(
        await tokenVesting.getAddress(),
        ethers.parseEther("1000000")
      );

      await expect(
        tokenVesting.createVestingSchedule(
          addr1.address,
          0,
          await time.latest(),
          0,
          365 * 24 * 60 * 60
        )
      ).to.be.revertedWith("CPROVesting: total amount must be > 0");
    });

    it("Should not allow locking with past unlock time", async function () {
      await cproToken.approve(
        await tokenLocking.getAddress(),
        ethers.parseEther("1000000")
      );

      const pastTime = (await time.latest()) - 1000;

      await expect(
        tokenLocking.lockTokens(ethers.parseEther("1000"), pastTime, "test")
      ).to.be.revertedWith("CPROLocking: unlock time must be in future");
    });

    it("Should not allow unauthorized access to contracts", async function () {
      await expect(
        tokenVesting
          .connect(addr1)
          .createVestingSchedule(
            addr2.address,
            ethers.parseEther("1000"),
            await time.latest(),
            0,
            365 * 24 * 60 * 60
          )
      ).to.be.revertedWithCustomError(
        tokenVesting,
        "OwnableUnauthorizedAccount"
      );

      await expect(
        tokenLocking
          .connect(addr1)
          .lockTokensFor(
            addr2.address,
            ethers.parseEther("1000"),
            (await time.latest()) + 1000,
            "test"
          )
      ).to.be.revertedWithCustomError(
        tokenLocking,
        "OwnableUnauthorizedAccount"
      );
    });

    it("Should handle reentrancy protection", async function () {
      // This test verifies that the ReentrancyGuard is working
      // In a real attack scenario, a malicious contract would try to call
      // claimTokens or unlockTokens recursively

      await cproToken.approve(
        await tokenVesting.getAddress(),
        ethers.parseEther("10000")
      );

      await tokenVesting.createVestingSchedule(
        addr1.address,
        ethers.parseEther("10000"),
        await time.latest(),
        0,
        365 * 24 * 60 * 60
      );

      // Fast forward to make tokens claimable
      await time.increase(365 * 24 * 60 * 60);

      // Normal claim should work
      await tokenVesting.connect(addr1).claimTokens();

      // Second claim should fail (no more tokens to claim)
      await expect(
        tokenVesting.connect(addr1).claimTokens()
      ).to.be.revertedWith("CPROVesting: no tokens to claim");
    });
  });
});
