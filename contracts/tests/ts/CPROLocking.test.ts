import { expect } from "chai";
import { network } from "hardhat";
const { ethers, networkHelpers } = await network.connect();

const ZERO = 0n;
const ONE = 1n;

const { time, loadFixture } = networkHelpers;

describe("CPROLocking", function () {
  /**
   * Deploys the mock token and locking, mints and funds the locking contract, returns helpers.
   */
  async function deployFixture() {
    const [owner, sweepRecipient, ...rest] = await ethers.getSigners();

    // Deploy mintable test token
    const MockERC20 = await ethers.getContractFactory("CPROToken");
    const token = await MockERC20.deploy();
    await token.waitForDeployment();

    // Mint a big supply to owner (100M)
    const initialOwnerSupply = ethers.parseUnits("100000000", 18);
    await (await token.mint(owner.address, initialOwnerSupply)).wait();

    const POOL = ethers.parseUnits("20000000", 18);
    const EXPECTED_BENEFICIARIES = Math.min(80, rest.length);

    const beneficiaries = rest.slice(0, EXPECTED_BENEFICIARIES);

    // Deploy locking
    const Locker = await ethers.getContractFactory("CPROLocking");
    const locker = await Locker.deploy(
      await token.getAddress(),
      POOL,
      EXPECTED_BENEFICIARIES,
      sweepRecipient.address
    );
    await locker.waitForDeployment();

    const share = await locker.sharePerBeneficiary();
    console.log("Share per beneficiary:", share.toString());

    // Approve and fund
    await token.connect(owner).approve(await locker.getAddress(), POOL);
    await locker.connect(owner).fund(POOL);

    return {
      owner,
      sweepRecipient,
      token,
      locker,
      POOL,
      EXPECTED_BENEFICIARIES,
      rest,
      beneficiaries,
    };
  }

  it("sets a fixed endTime ~1 year in the future at deployment", async function () {
    const { locker } = await loadFixture(deployFixture);
    const endTime = await locker.endTime();
    const now = await time.latest();
    expect(endTime - BigInt(now)).to.be.greaterThan(300n * 24n * 60n * 60n); // >300 days
    expect(endTime - BigInt(now)).to.be.lessThan(370n * 24n * 60n * 60n); // <370 days
  });

  it("funds the locker with exactly 20000000 CPRO", async function () {
    const { token, locker, POOL } = await loadFixture(deployFixture);
    const bal = await token.balanceOf(await locker.getAddress());
    expect(bal).to.equal(POOL);
  });

  it("adds up to 80 beneficiaries and ensures equal share per beneficiary", async function () {
    const { locker, EXPECTED_BENEFICIARIES, beneficiaries, POOL } =
      await loadFixture(deployFixture);

    const share = await locker.sharePerBeneficiary();
    expect(share).to.equal(POOL / BigInt(EXPECTED_BENEFICIARIES));

    for (let i = 0; i < beneficiaries.length; i++) {
      const lt = i % 6;
      await expect(locker.addBeneficiary(beneficiaries[i].address, lt)).to.emit(
        locker,
        "BeneficiaryAdded"
      );
    }

    const count = await locker.beneficiariesCount();
    expect(count).to.equal(BigInt(beneficiaries.length));

    for (let i = 0; i < Math.min(5, beneficiaries.length); i++) {
      const [lockId, amount, unlockTime, claimed, lockTypeId] =
        await locker.getBeneficiaryLockInfo(beneficiaries[i].address);
      expect(lockId).to.be.greaterThan(ZERO);
      expect(amount).to.equal(share);
      expect(unlockTime).to.equal(await locker.endTime());
      expect(claimed).to.equal(false);
      expect(lockTypeId).to.equal(BigInt(i % 6));
    }

    const totalAssigned = await locker.totalAssigned();
    expect(totalAssigned).to.equal(share * BigInt(beneficiaries.length));

    const reserved = await locker.reservedForUnclaimed();
    expect(reserved).to.equal(totalAssigned);
  });

  it("reverts claim before deadline", async function () {
    const { locker, beneficiaries } = await loadFixture(deployFixture);

    for (let i = 0; i < beneficiaries.length; i++) {
      await locker.addBeneficiary(beneficiaries[i].address, i % 3);
    }

    await expect(
      locker.connect(beneficiaries[0]).claim()
    ).to.be.revertedWithCustomError(locker, "BeforeDeadline");
  });

  it("after 1 year: all beneficiaries can claim, all receive the same amount, totals are correct", async function () {
    const { token, locker, beneficiaries, POOL, owner } = await loadFixture(
      deployFixture
    );

    // Add everyone before deadline
    for (let i = 0; i < beneficiaries.length; i++) {
      await locker
        .connect(owner)
        .addBeneficiary(beneficiaries[i].address, i % 5);
    }
    const share = await locker.sharePerBeneficiary();
    const endTime = await locker.endTime();

    // advance time
    await time.increaseTo(endTime + ONE);
    await ethers.provider.send("evm_mine");

    const currentTime = await time.latest();
    console.log("currentTime >= endTime:", currentTime >= endTime);

    for (let i = 0; i < beneficiaries.length; i++) {
      const can = await locker.canClaim(beneficiaries[i].address);
      expect(can).to.equal(true);
    }

    const beforeBalances = await Promise.all(
      beneficiaries.map((b) => token.balanceOf(b.address))
    );

    // Everyone claims, assert claim event
    for (let i = 0; i < beneficiaries.length; i++) {
      await expect(locker.connect(beneficiaries[i]).claim())
        .to.emit(locker, "Claimed")
        .withArgs(
          beneficiaries[i].address,
          await locker.beneficiaryLockId(beneficiaries[i].address),
          share
        )
        .and.to.emit(token, "Transfer")
        .withArgs(await locker.getAddress(), beneficiaries[i].address, share);

      const [lockId, amount, unlockTime, claimed] =
        await locker.getBeneficiaryLockInfo(beneficiaries[i].address);

      expect(amount).to.equal(share);
      expect(unlockTime).to.equal(endTime);
      expect(claimed).to.equal(true);
    }

    const afterBalances = await Promise.all(
      beneficiaries.map((b) => token.balanceOf(b.address))
    );

    for (let i = 0; i < beneficiaries.length; i++) {
      const diff = afterBalances[i] - beforeBalances[i];
      expect(diff).to.equal(share);
    }

    const totalAssigned = await locker.totalAssigned();
    const totalClaimed = await locker.totalClaimed();

    expect(totalAssigned).to.equal(share * BigInt(beneficiaries.length));
    expect(totalClaimed).to.equal(share * BigInt(beneficiaries.length));

    const reserved = await locker.reservedForUnclaimed();
    expect(reserved).to.equal(ZERO);

    const lockerBal = await token.balanceOf(await locker.getAddress());
    expect(lockerBal).to.equal(POOL - totalClaimed);
  });

  it("all beneficiaries have the same share value", async function () {
    const { locker, beneficiaries } = await loadFixture(deployFixture);

    for (let i = 0; i < beneficiaries.length; i++) {
      await locker.addBeneficiary(beneficiaries[i].address, i % 4);
    }

    const share = await locker.sharePerBeneficiary();

    for (let i = 0; i < beneficiaries.length; i++) {
      const a = await locker.allocation(beneficiaries[i].address);
      expect(a).to.equal(share);
    }
  });

  it("getLockInfo should return with correct information", async function () {
    const { locker, beneficiaries } = await loadFixture(deployFixture);
    const b0 = beneficiaries[0];
    const b1 = beneficiaries[1];

    await locker.addBeneficiary(b0.address, 2);
    await locker.addBeneficiary(b1.address, 3);

    const b0LockId = await locker.beneficiaryLockId(b0.address);
    const b1LockId = await locker.beneficiaryLockId(b1.address);
    const share = await locker.sharePerBeneficiary();
    const endTime = await locker.endTime();

    // Before deadline
    {
      const [owner0, amount0, unlock0, claimed0, lt0] =
        await locker.getLockInfo(b0LockId);
      expect(owner0).to.equal(b0.address);
      expect(amount0).to.equal(share);
      expect(unlock0).to.equal(endTime);
      expect(claimed0).to.equal(false);
      expect(lt0).to.equal(2n);
    }

    // Time travel and claim for b0
    await time.increaseTo(endTime + ONE);
    await locker.connect(b0).claim();

    {
      const [owner0, amount0, unlock0, claimed0, lt0] =
        await locker.getLockInfo(b0LockId);
      expect(owner0).to.equal(b0.address);
      expect(amount0).to.equal(share);
      expect(unlock0).to.equal(endTime);
      expect(claimed0).to.equal(true);
      expect(lt0).to.equal(2n);
    }

    // b1 still unclaimed
    {
      const [owner1, amount1, unlock1, claimed1, lt1] =
        await locker.getLockInfo(b1LockId);
      expect(owner1).to.equal(b1.address);
      expect(amount1).to.equal(share);
      expect(unlock1).to.equal(endTime);
      expect(claimed1).to.equal(false);
      expect(lt1).to.equal(3n);
    }
  });
});
