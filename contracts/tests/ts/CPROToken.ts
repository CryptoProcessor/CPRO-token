import { expect } from "chai";
import { network } from "hardhat";
const { ethers } = await network.connect();

describe("CPROToken", function () {
  let token, owner, addr1, addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    const CPROToken = await ethers.getContractFactory("CPROToken");
    token = await CPROToken.deploy();
    await token.waitForDeployment();
  });

  it("Should deploy with initial supply to owner", async function () {
    const ownerBalance = await token.balanceOf(owner.address);
    expect(ownerBalance).to.equal(ethers.parseUnits("1000000", 18));
  });

  it("Owner can mint tokens", async function () {
    const mintAmount = ethers.parseUnits("1000", 18);

    const tx = await token.mint(addr1.address, mintAmount);
    await expect(tx)
      .to.emit(token, "TokensMinted")
      .withArgs(addr1.address, mintAmount);

    const balance = await token.balanceOf(addr1.address);
    expect(balance).to.equal(mintAmount);
  });

  it("Should not exceed MAX_SUPPLY", async function () {
    const tooMuch = await token.MAX_SUPPLY();
    await expect(token.mint(addr1.address, tooMuch)).to.be.revertedWith(
      "CPROToken: Cap exceeded"
    );
  });

  it("Owner can burn from their own balance", async function () {
    const burnAmount = ethers.parseUnits("100", 18);

    const tx = await token.burnFromOwner(burnAmount);
    await expect(tx).to.emit(token, "TokensBurnedByOwner").withArgs(burnAmount);

    const ownerBalance = await token.balanceOf(owner.address);
    expect(ownerBalance).to.equal(
      ethers.parseUnits("1000000", 18) - burnAmount
    );
  });

  it("Non-owner cannot mint or burn", async function () {
    await expect(token.connect(addr1).mint(addr1.address, 1000)).to.be.revert(
      ethers
    ); // onlyOwner modifier

    await expect(token.connect(addr1).burnFromOwner(1000)).to.be.revert(ethers);
  });

  it("Pause and unpause should work", async function () {
    await token.pause();
    await expect(
      token.transfer(addr1.address, 1000)
    ).to.be.revertedWithCustomError(token, "EnforcedPause");

    await token.unpause();
    await expect(token.transfer(addr1.address, 1000))
      .to.emit(token, "Transfer")
      .withArgs(owner.address, addr1.address, 1000);
  });

  it("Owner can recover ERC20 tokens", async function () {
    const DummyERC20 = await ethers.getContractFactory("DummyERC20");
    const dummy = await DummyERC20.deploy();
    await dummy.waitForDeployment();

    // Mint dummy tokens to CPROToken contract
    await dummy.mint(token.target, 1000);

    await expect(token.recoverERC20(dummy.target, 500))
      .to.emit(token, "TokensRecovered")
      .withArgs(dummy.target, 500);

    expect(await dummy.balanceOf(owner.address)).to.equal(500);
  });

  it("Should measure gas cost for mint", async function () {
    const mintAmount = ethers.parseUnits("500", 18);
    const tx = await token.mint(addr1.address, mintAmount);
    const receipt = await tx.wait();

    console.log("Mint Gas Used:", receipt.gasUsed.toString());
    console.log(
      "Gas Cost in ETH:",
      ethers.formatEther(receipt.gasUsed * tx.gasPrice)
    );
  });
});
