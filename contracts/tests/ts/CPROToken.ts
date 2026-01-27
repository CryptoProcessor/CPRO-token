import { expect } from "chai";
import { network } from "hardhat";
const { ethers } = await network.connect();

describe("CPROToken", function () {
  let token, owner, addr1, addr2, feeRecipient, dexPair;

  beforeEach(async function () {
    [owner, addr1, addr2, feeRecipient, dexPair] = await ethers.getSigners();

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

  // Transfer Fee Tests
  describe("Transfer Fee Configuration", function () {
    it("Owner can set transfer fee", async function () {
      const feeBasisPoints = 100; // 1%
      await expect(token.setTransferFee(feeBasisPoints))
        .to.emit(token, "TransferFeeUpdated")
        .withArgs(0, feeBasisPoints);
      
      expect(await token.transferFeeBasisPoints()).to.equal(feeBasisPoints);
    });

    it("Non-owner cannot set transfer fee", async function () {
      await expect(
        token.connect(addr1).setTransferFee(100)
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");
    });

    it("Cannot set fee above maximum", async function () {
      const maxFee = await token.MAX_FEE_BASIS_POINTS();
      await expect(
        token.setTransferFee(maxFee + 1n)
      ).to.be.revertedWith("CPROToken: Fee too high");
    });

    it("Owner can set fee recipient", async function () {
      await expect(token.setFeeRecipient(feeRecipient.address))
        .to.emit(token, "FeeRecipientUpdated")
        .withArgs(ethers.ZeroAddress, feeRecipient.address);
      
      expect(await token.feeRecipient()).to.equal(feeRecipient.address);
    });

    it("Cannot set zero address as fee recipient", async function () {
      await expect(
        token.setFeeRecipient(ethers.ZeroAddress)
      ).to.be.revertedWith("CPROToken: Invalid recipient");
    });

    it("Cannot set contract address as fee recipient", async function () {
      await expect(
        token.setFeeRecipient(token.target)
      ).to.be.revertedWith("CPROToken: Cannot use contract as recipient");
    });

    it("Owner can enable/disable transfer fees", async function () {
      await expect(token.setTransferFeeEnabled(true))
        .to.emit(token, "TransferFeeToggled")
        .withArgs(true);
      
      expect(await token.transferFeeEnabled()).to.be.true;

      await expect(token.setTransferFeeEnabled(false))
        .to.emit(token, "TransferFeeToggled")
        .withArgs(false);
      
      expect(await token.transferFeeEnabled()).to.be.false;
    });
  });

  describe("Transfer Fee Functionality", function () {
    beforeEach(async function () {
      await token.setTransferFee(100); // 1%
      await token.setFeeRecipient(feeRecipient.address);
      await token.setTransferFeeEnabled(true);
    });

    it("Should deduct fee from transfer", async function () {
      const transferAmount = ethers.parseUnits("1000", 18);
      const expectedFee = (transferAmount * 100n) / 10000n;
      const expectedTransfer = transferAmount - expectedFee;

      await token.transfer(addr1.address, transferAmount);

      expect(await token.balanceOf(addr1.address)).to.equal(expectedTransfer);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(expectedFee);
    });

    it("Should not charge fee when disabled", async function () {
      await token.setTransferFeeEnabled(false);
      
      const transferAmount = ethers.parseUnits("1000", 18);
      await token.transfer(addr1.address, transferAmount);

      expect(await token.balanceOf(addr1.address)).to.equal(transferAmount);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(0);
    });

    it("Should not charge fee on minting", async function () {
      const mintAmount = ethers.parseUnits("1000", 18);
      const feeRecipientBalanceBefore = await token.balanceOf(feeRecipient.address);

      await token.mint(addr1.address, mintAmount);

      expect(await token.balanceOf(addr1.address)).to.equal(mintAmount);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(feeRecipientBalanceBefore);
    });

    it("Should NOT charge fee on burning", async function () {
      const burnAmount = ethers.parseUnits("1000", 18);
      const feeRecipientBalanceBefore = await token.balanceOf(feeRecipient.address);
      const totalSupplyBefore = await token.totalSupply();

      // Burning should be deterministic - burn exactly burnAmount
      await token.burn(burnAmount);

      // Fee recipient should not receive anything
      expect(await token.balanceOf(feeRecipient.address)).to.equal(
        feeRecipientBalanceBefore
      );
      
      // Total supply should decrease by exactly burnAmount
      expect(await token.totalSupply()).to.equal(totalSupplyBefore - burnAmount);
    });

    it("Should NOT charge fee on transfer to zero address", async function () {
      const burnAmount = ethers.parseUnits("1000", 18);
      const feeRecipientBalanceBefore = await token.balanceOf(feeRecipient.address);
      const totalSupplyBefore = await token.totalSupply();

      // Transfer to address(0) should NOT charge fee (burning)
      await token.transfer(ethers.ZeroAddress, burnAmount);

      // Fee recipient should not receive anything
      expect(await token.balanceOf(feeRecipient.address)).to.equal(
        feeRecipientBalanceBefore
      );
      
      // Total supply should decrease by exactly burnAmount
      expect(await token.totalSupply()).to.equal(totalSupplyBefore - burnAmount);
    });

    it("Should work with transferFrom", async function () {
      const transferAmount = ethers.parseUnits("1000", 18);
      const expectedFee = (transferAmount * 100n) / 10000n;
      const expectedTransfer = transferAmount - expectedFee;

      await token.approve(addr1.address, transferAmount);
      await token.connect(addr1).transferFrom(owner.address, addr2.address, transferAmount);

      expect(await token.balanceOf(addr2.address)).to.equal(expectedTransfer);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(expectedFee);
    });

    it("Should work with pause/unpause", async function () {
      await token.pause();
      await expect(
        token.transfer(addr1.address, ethers.parseUnits("1000", 18))
      ).to.be.revertedWithCustomError(token, "EnforcedPause");

      await token.unpause();
      const transferAmount = ethers.parseUnits("1000", 18);
      const expectedFee = (transferAmount * 100n) / 10000n;
      const expectedTransfer = transferAmount - expectedFee;

      await token.transfer(addr1.address, transferAmount);

      expect(await token.balanceOf(addr1.address)).to.equal(expectedTransfer);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(expectedFee);
    });

    it("Should burn fees when feeRecipient is not set", async function () {
      // Don't set feeRecipient - it should remain address(0)
      const transferAmount = ethers.parseUnits("1000", 18);
      const expectedFee = (transferAmount * 100n) / 10000n;
      const expectedTransfer = transferAmount - expectedFee;
      const totalSupplyBefore = await token.totalSupply();

      // Fee should be explicitly burned when recipient is address(0)
      await token.transfer(addr1.address, transferAmount);

      expect(await token.balanceOf(addr1.address)).to.equal(expectedTransfer);
      expect(await token.totalSupply()).to.equal(totalSupplyBefore - expectedFee); // Supply decreases by fee amount
      
      // Verify ERC20 invariant: totalSupply should equal sum of balances
      const totalBalances = (await token.balanceOf(owner.address)) + (await token.balanceOf(addr1.address));
      expect(await token.totalSupply()).to.equal(totalBalances);
    });
  });

  describe("Transfer Fee Voting Power", function () {
    beforeEach(async function () {
      await token.setTransferFee(100); // 1%
      await token.setFeeRecipient(feeRecipient.address);
      await token.setTransferFeeEnabled(true);
    });

    it("Should update voting power correctly with fees", async function () {
      const transferAmount = ethers.parseUnits("1000", 18);
      const expectedFee = (transferAmount * 100n) / 10000n;
      const expectedTransfer = transferAmount - expectedFee;

      const ownerVotesBefore = await token.getVotes(owner.address);
      const addr1VotesBefore = await token.getVotes(addr1.address);
      const feeRecipientVotesBefore = await token.getVotes(feeRecipient.address);

      await token.transfer(addr1.address, transferAmount);

      // Move to next block to update checkpoints
      await ethers.provider.send("evm_mine", []);

      const ownerVotesAfter = await token.getVotes(owner.address);
      const addr1VotesAfter = await token.getVotes(addr1.address);
      const feeRecipientVotesAfter = await token.getVotes(feeRecipient.address);

      expect(ownerVotesBefore - ownerVotesAfter).to.equal(transferAmount);
      expect(addr1VotesAfter - addr1VotesBefore).to.equal(expectedTransfer);
      expect(feeRecipientVotesAfter - feeRecipientVotesBefore).to.equal(expectedFee);
    });

    it("Should update voting power correctly when fees are burned", async function () {
      // Don't set feeRecipient - fees will be burned
      await token.setTransferFee(100); // 1%
      // feeRecipient remains address(0) - fees will be burned
      await token.setTransferFeeEnabled(true);

      const transferAmount = ethers.parseUnits("1000", 18);
      const expectedFee = (transferAmount * 100n) / 10000n;

      const ownerVotesBefore = await token.getVotes(owner.address);
      const addr1VotesBefore = await token.getVotes(addr1.address);

      await token.transfer(addr1.address, transferAmount);

      // Move to next block to update checkpoints
      await ethers.provider.send("evm_mine", []);

      const ownerVotesAfter = await token.getVotes(owner.address);
      const addr1VotesAfter = await token.getVotes(addr1.address);

      // Owner's voting power should decrease by full amount (transfer + fee)
      expect(ownerVotesBefore - ownerVotesAfter).to.equal(transferAmount);
      
      // User1's voting power should increase by transfer amount minus fee
      expect(addr1VotesAfter - addr1VotesBefore).to.equal(transferAmount - expectedFee);
      
      // Fee was burned, so no one's voting power should increase by the fee
      // Total voting power should decrease by the fee amount (burned)
    });
  });

  describe("Fee Exemption", function () {
    beforeEach(async function () {
      await token.setTransferFee(100); // 1%
      await token.setFeeRecipient(feeRecipient.address);
      await token.setTransferFeeEnabled(true);
    });

    it("Owner can set fee exemption", async function () {
      await expect(token.setFeeExemption(dexPair.address, true))
        .to.emit(token, "FeeExemptionUpdated")
        .withArgs(dexPair.address, true);
      
      expect(await token.isFeeExempt(dexPair.address)).to.be.true;

      await expect(token.setFeeExemption(dexPair.address, false))
        .to.emit(token, "FeeExemptionUpdated")
        .withArgs(dexPair.address, false);
      
      expect(await token.isFeeExempt(dexPair.address)).to.be.false;
    });

    it("Non-owner cannot set fee exemption", async function () {
      await expect(
        token.connect(addr1).setFeeExemption(dexPair.address, true)
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");
    });

    it("Cannot set exemption for zero address", async function () {
      await expect(
        token.setFeeExemption(ethers.ZeroAddress, true)
      ).to.be.revertedWith("CPROToken: Invalid account");
    });

    it("Transfer from exempt address should not charge fee", async function () {
      await token.setFeeExemption(owner.address, true);
      
      const transferAmount = ethers.parseUnits("1000", 18);
      const feeRecipientBalanceBefore = await token.balanceOf(feeRecipient.address);

      await token.transfer(addr1.address, transferAmount);

      expect(await token.balanceOf(addr1.address)).to.equal(transferAmount);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(feeRecipientBalanceBefore);
    });

    it("Transfer to exempt address should not charge fee", async function () {
      await token.setFeeExemption(addr1.address, true);
      
      const transferAmount = ethers.parseUnits("1000", 18);
      const feeRecipientBalanceBefore = await token.balanceOf(feeRecipient.address);

      await token.transfer(addr1.address, transferAmount);

      expect(await token.balanceOf(addr1.address)).to.equal(transferAmount);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(feeRecipientBalanceBefore);
    });

    it("Transfer between exempt addresses should not charge fee", async function () {
      await token.setFeeExemption(owner.address, true);
      await token.setFeeExemption(addr1.address, true);
      
      const transferAmount = ethers.parseUnits("1000", 18);
      const feeRecipientBalanceBefore = await token.balanceOf(feeRecipient.address);

      await token.transfer(addr1.address, transferAmount);

      expect(await token.balanceOf(addr1.address)).to.equal(transferAmount);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(feeRecipientBalanceBefore);
    });

    it("Batch set fee exemptions", async function () {
      const accounts = [dexPair.address, addr1.address];
      const exempts = [true, false];

      await token.batchSetFeeExemptions(accounts, exempts);

      expect(await token.isFeeExempt(dexPair.address)).to.be.true;
      expect(await token.isFeeExempt(addr1.address)).to.be.false;
    });

    it("Batch set fee exemptions - arrays length mismatch", async function () {
      const accounts = [dexPair.address, addr1.address];
      const exempts = [true];

      await expect(
        token.batchSetFeeExemptions(accounts, exempts)
      ).to.be.revertedWith("CPROToken: Arrays length mismatch");
    });

    it("Batch set fee exemptions - empty arrays", async function () {
      const accounts = [];
      const exempts = [];

      await expect(
        token.batchSetFeeExemptions(accounts, exempts)
      ).to.be.revertedWith("CPROToken: Empty arrays");
    });

    it("DEX pair scenario - no fees", async function () {
      await token.setFeeExemption(dexPair.address, true);

      // User transfers to DEX pair (no fee)
      const amount = ethers.parseUnits("1000", 18);
      await token.transfer(dexPair.address, amount);
      expect(await token.balanceOf(dexPair.address)).to.equal(amount);

      // DEX pair transfers to user (no fee)
      await token.connect(dexPair).transfer(addr1.address, amount);
      expect(await token.balanceOf(addr1.address)).to.equal(amount);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(0);
    });
  });
});
