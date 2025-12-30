import { expect } from "chai";
import { network } from "hardhat";
const { ethers } = await network.connect();

describe("CPROVesting", function () {
  let Token, Vesting, token, vesting;
  let owner, beneficiary, other;

  beforeEach(async function () {
    [owner, beneficiary, other] = await ethers.getSigners();

    // Deploy token (1 million CPRO)
    Token = await ethers.getContractFactory("CPROToken");
    token = await Token.deploy(); //CPRO token doesnt have any constructor arguments
    await token.waitForDeployment();

    // Deploy vesting
    Vesting = await ethers.getContractFactory("CPROVesting");
    vesting = await Vesting.deploy(await token.getAddress());
    await vesting.waitForDeployment();

    // Owner approves vesting contract to pull tokens
    await token.approve(
      await vesting.getAddress(),
      ethers.parseEther("1000000")
    );
  });

  it("should create a vesting schedule", async function () {
    const now = (await ethers.provider.getBlock("latest")).timestamp;

    await vesting.createVestingSchedule(
      beneficiary.address,
      ethers.parseEther("1000"),
      now,
      60, // cliff = 1 minute
      600 // duration = 10 minutes
    );

    const schedule = await vesting.getBeneficiaryVestingSchedule(
      beneficiary.address
    );
    expect(schedule.totalAmount).to.equal(ethers.parseEther("1000"));
    expect(schedule.revoked).to.equal(false);
  });

  it("should not allow claims before cliff", async function () {
    const now = (await ethers.provider.getBlock("latest")).timestamp;

    await vesting.createVestingSchedule(
      beneficiary.address,
      ethers.parseEther("1000"),
      now,
      60,
      600
    );

    await expect(vesting.connect(beneficiary).claimTokens()).to.be.revertedWith(
      "CPROVesting: no tokens to claim"
    );
  });

  it("should allow partial claim after cliff", async function () {
    const now = (await ethers.provider.getBlock("latest")).timestamp;

    await vesting.createVestingSchedule(
      beneficiary.address,
      ethers.parseEther("1000"),
      now,
      1, // 1 second cliff
      10 // 10 seconds duration
    );

    // MOve forward past cliff
    await ethers.provider.send("evm_increaseTime", [5]);
    await ethers.provider.send("evm_mine");

    await vesting.connect(beneficiary).claimTokens();

    const balance = await token.balanceOf(beneficiary.address);
    expect(balance).to.be.gt(0);
  });

  it("should settle correctly on revoke", async function () {
    const now = (await ethers.provider.getBlock("latest")).timestamp;

    await vesting.createVestingSchedule(
      beneficiary.address,
      ethers.parseEther("1000"),
      now,
      1,
      10
    );

    // Time travel halfway
    await ethers.provider.send("evm_increaseTime", [5]);
    await ethers.provider.send("evm_mine");

    // Revoke
    await vesting.revokeVesting(beneficiary.address);

    const beneficiaryBalance = await token.balanceOf(beneficiary.address);
    const ownerBalance = await token.balanceOf(owner.address);

    // Beneficiary should have vested portion, owner gets back unvested
    expect(beneficiaryBalance).to.be.gt(0);
    expect(ownerBalance).to.be.gt(0);
  });
});
