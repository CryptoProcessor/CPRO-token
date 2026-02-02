// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {CPROToken} from "../CPROToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Mock ERC20 token for testing recovery functionality
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

// Mock ERC20 that reverts on transfer (e.g. non-standard / USDT-style behavior)
contract MockERC20RevertsOnTransfer is ERC20 {
    constructor() ERC20("MockRevert", "MREV") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert("Token transfer reverted");
    }
}

contract CPROTokenTest is Test {
    CPROToken public token;
    MockERC20 public mockToken;
    MockERC20RevertsOnTransfer public mockRevertingToken;

    address public owner;
    address public user1;
    address public user2;
    address public nonOwner;
    address public feeRecipient;
    address public dexPair;
    address public stakingContract;

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurnedByOwner(uint256 amount);
    event TokensRecovered(address indexed tokenAddress, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Paused(address account);
    event Unpaused(address account);
    event TransferFeeUpdated(uint256 oldBasisPoints, uint256 newBasisPoints);
    event FeeRecipientUpdated(
        address indexed oldRecipient,
        address indexed newRecipient
    );
    event TransferFeeToggled(bool enabled);
    event FeeExemptionUpdated(address indexed account, bool exempt);
    event FeeExemptionSet(address[] accounts, bool[] exempts);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");
        feeRecipient = makeAddr("feeRecipient");
        dexPair = makeAddr("dexPair");
        stakingContract = makeAddr("stakingContract");

        token = new CPROToken();
        mockToken = new MockERC20();
        mockRevertingToken = new MockERC20RevertsOnTransfer();
    }

    // Constructor
    function testConstructor() public view {
        assertEq(token.name(), "CPROToken");
        assertEq(token.symbol(), "CPRO");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.owner(), owner);
        assertEq(token.cap(), MAX_SUPPLY);
        assertFalse(token.paused());
    }

    // Minting
    function testMint() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user1, mintAmount);

        token.mint(user1, mintAmount);

        assertEq(token.totalSupply(), initialSupply + mintAmount);
        assertEq(token.balanceOf(user1), initialBalance + mintAmount);
    }

    function testMintOnlyOwner() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.mint(user1, mintAmount);
    }

    function testMintCapExceeded() public {
        uint256 remainingSupply = MAX_SUPPLY - token.totalSupply();
        uint256 excessAmount = remainingSupply + 1;

        vm.expectRevert("CPROToken: Cap exceeded");
        token.mint(user1, excessAmount);
    }

    function testMintExactlyCap() public {
        uint256 remainingSupply = MAX_SUPPLY - token.totalSupply();

        token.mint(user1, remainingSupply);

        assertEq(token.totalSupply(), MAX_SUPPLY);
        assertEq(token.balanceOf(user1), remainingSupply);
    }

    // Burning
    function testBurnFromOwner() public {
        uint256 burnAmount = 100 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit TokensBurnedByOwner(burnAmount);

        token.burnFromOwner(burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(owner), initialBalance - burnAmount);
    }

    function testBurnFromOwnerOnlyOwner() public {
        uint256 burnAmount = 100 * 10 ** 18;

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.burnFromOwner(burnAmount);
    }

    function testBurnFromOwnerInsufficientBalance() public {
        uint256 burnAmount = token.balanceOf(owner) + 1;

        vm.expectRevert();
        token.burnFromOwner(burnAmount);
    }

    // ERC20Burnable
    function testBurn() public {
        uint256 burnAmount = 100 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(owner);

        token.burn(burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(owner), initialBalance - burnAmount);
    }

    function testBurnFrom() public {
        uint256 burnAmount = 100 * 10 ** 18;

        // Give user1 some tokens
        token.mint(user1, burnAmount * 2);

        // User1 approves owner to burn tokens
        vm.prank(user1);
        token.approve(owner, burnAmount);

        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(user1);

        token.burnFrom(user1, burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(user1), initialBalance - burnAmount);
        assertEq(token.allowance(user1, owner), 0);
    }

    // Pause/Unpause
    function testPause() public {
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);

        token.pause();

        assertTrue(token.paused());
    }

    function testUnpause() public {
        token.pause();
        assertTrue(token.paused());

        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);

        token.unpause();

        assertFalse(token.paused());
    }

    function testPauseOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.pause();
    }

    function testUnpauseOnlyOwner() public {
        token.pause();

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.unpause();
    }

    function testTransferWhenPaused() public {
        token.mint(user1, 1000 * 10 ** 18);
        token.pause();

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 * 10 ** 18);
    }

    function testMintWhenPaused() public {
        token.pause();

        vm.expectRevert();
        token.mint(user1, 1000 * 10 ** 18);
    }

    function testBurnFromOwnerWhenPaused() public {
        token.pause();
        vm.expectRevert();
        token.burnFromOwner(100 * 10 ** 18);
    }

    function testSetTransferFeeWhenPaused() public {
        token.pause();
        vm.expectRevert();
        token.setTransferFee(100);
    }

    function testSetFeeRecipientWhenPaused() public {
        token.pause();
        vm.expectRevert();
        token.setFeeRecipient(feeRecipient);
    }

    function testSetTransferFeeEnabledWhenPaused() public {
        token.pause();
        vm.expectRevert();
        token.setTransferFeeEnabled(true);
    }

    function testSetFeeExemptionWhenPaused() public {
        token.pause();
        vm.expectRevert();
        token.setFeeExemption(dexPair, true);
    }

    function testBatchSetFeeExemptionsWhenPaused() public {
        address[] memory accounts = new address[](1);
        bool[] memory exempts = new bool[](1);
        accounts[0] = dexPair;
        exempts[0] = true;
        token.pause();
        vm.expectRevert();
        token.batchSetFeeExemptions(accounts, exempts);
    }

    function testRecoverERC20WhenPaused() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;
        mockToken.transfer(address(token), recoveryAmount);
        token.pause();
        vm.expectRevert();
        token.recoverERC20(address(mockToken), recoveryAmount);
    }

    // Recovery
    function testRecoverERC20() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;

        // Send mock tokens to the CPRO contract
        mockToken.transfer(address(token), recoveryAmount);
        assertEq(mockToken.balanceOf(address(token)), recoveryAmount);

        uint256 initialOwnerBalance = mockToken.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit TokensRecovered(address(mockToken), recoveryAmount);

        token.recoverERC20(address(mockToken), recoveryAmount);

        assertEq(mockToken.balanceOf(address(token)), 0);
        assertEq(
            mockToken.balanceOf(owner),
            initialOwnerBalance + recoveryAmount
        );
    }

    function testRecoverERC20OnlyOwner() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.recoverERC20(address(mockToken), recoveryAmount);
    }

    function testRecoverERC20CannotRecoverOwnTokens() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;

        vm.expectRevert("CPROToken: Cannot recover own tokens");
        token.recoverERC20(address(token), recoveryAmount);
    }

    function testRecoverERC20InvalidTokenAddress() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;

        vm.expectRevert("CPROToken: Invalid token address");
        token.recoverERC20(address(0), recoveryAmount);
    }

    function testRecoverERC20ZeroAmount() public {
        vm.expectRevert("CPROToken: Amount must be greater than 0");
        token.recoverERC20(address(mockToken), 0);
    }

    function testRecoverERC20TokenTransferFailed() public {
        uint256 recoveryAmount = 1000 * 10 ** 18;
        mockRevertingToken.transfer(address(token), recoveryAmount);
        assertEq(mockRevertingToken.balanceOf(address(token)), recoveryAmount);

        vm.expectRevert("CPROToken: Token transfer failed");
        token.recoverERC20(address(mockRevertingToken), recoveryAmount);
    }

    // Transfer Tests
    function testTransfer() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, transferAmount);

        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function testTransferFrom() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        // Approve user1 to spend owner's tokens
        token.approve(user1, transferAmount);

        vm.prank(user1);
        token.transferFrom(owner, user2, transferAmount);

        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
        assertEq(token.allowance(owner, user1), 0);
    }

    // Edge Cases and Fuzz Tests
    function testFuzzMint(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY - token.totalSupply());

        uint256 initialSupply = token.totalSupply();
        token.mint(user1, amount);

        assertEq(token.totalSupply(), initialSupply + amount);
        assertEq(token.balanceOf(user1), amount);
    }

    function testFuzzBurnFromOwner(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(owner));

        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(owner);

        token.burnFromOwner(amount);

        assertEq(token.totalSupply(), initialSupply - amount);
        assertEq(token.balanceOf(owner), initialBalance - amount);
    }

    function testMultipleMintAndBurn() public {
        uint256 mintAmount1 = 1000 * 10 ** 18;
        uint256 mintAmount2 = 2000 * 10 ** 18;
        uint256 burnAmount = 500 * 10 ** 18;

        uint256 initialSupply = token.totalSupply();

        // Multiple mints
        token.mint(user1, mintAmount1);
        token.mint(user2, mintAmount2);

        // Burn from owner
        token.burnFromOwner(burnAmount);

        uint256 expectedSupply = initialSupply +
            mintAmount1 +
            mintAmount2 -
            burnAmount;
        assertEq(token.totalSupply(), expectedSupply);
        assertEq(token.balanceOf(user1), mintAmount1);
        assertEq(token.balanceOf(user2), mintAmount2);
    }

    // Gas optimization tests
    function testGasMint() public {
        uint256 gasStart = gasleft();
        token.mint(user1, 1000 * 10 ** 18);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for mint:", gasUsed);
        assertTrue(gasUsed > 0); // Simple assertion to make it a proper test
    }

    // ============ Transfer Fee Tests ============

    // Configuration Tests
    function testSetTransferFee() public {
        uint256 feeBasisPoints = 100; // 1%

        vm.expectEmit(true, false, false, true);
        emit TransferFeeUpdated(0, feeBasisPoints);

        token.setTransferFee(feeBasisPoints);
        assertEq(token.transferFeeBasisPoints(), feeBasisPoints);
    }

    function testSetTransferFeeOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.setTransferFee(100);
    }

    function testSetTransferFeeTooHigh() public {
        vm.expectRevert("CPROToken: Fee too high");
        token.setTransferFee(token.MAX_FEE_BASIS_POINTS() + 1);
    }

    function testSetTransferFeeMaxAllowed() public {
        uint256 maxFee = token.MAX_FEE_BASIS_POINTS();
        token.setTransferFee(maxFee);
        assertEq(token.transferFeeBasisPoints(), maxFee);
    }

    function testSetFeeRecipient() public {
        vm.expectEmit(true, true, false, true);
        emit FeeRecipientUpdated(address(0), feeRecipient);

        token.setFeeRecipient(feeRecipient);
        assertEq(token.feeRecipient(), feeRecipient);
    }

    function testSetFeeRecipientOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.setFeeRecipient(feeRecipient);
    }

    function testSetFeeRecipientZeroAddress() public {
        vm.expectRevert("CPROToken: Invalid recipient");
        token.setFeeRecipient(address(0));
    }

    function testSetFeeRecipientContractAddress() public {
        vm.expectRevert("CPROToken: Cannot use contract as recipient");
        token.setFeeRecipient(address(token));
    }

    function testSetTransferFeeEnabled() public {
        vm.expectEmit(true, false, false, true);
        emit TransferFeeToggled(true);

        token.setTransferFeeEnabled(true);
        assertTrue(token.transferFeeEnabled());

        vm.expectEmit(true, false, false, true);
        emit TransferFeeToggled(false);

        token.setTransferFeeEnabled(false);
        assertFalse(token.transferFeeEnabled());
    }

    function testSetTransferFeeEnabledOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.setTransferFeeEnabled(true);
    }

    // Basic Fee Functionality
    function testTransferWithFee() public {
        // Setup: Enable 1% fee (100 basis points)
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000; // 1% = 10 tokens
        uint256 expectedTransfer = transferAmount - expectedFee;

        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), expectedTransfer);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function testTransferWithFeeDisabled() public {
        // Setup fee but keep it disabled
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(false);

        uint256 transferAmount = 1000 * 10 ** 18;

        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(feeRecipient), 0);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function testTransferFromWithFee() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;
        uint256 expectedTransfer = transferAmount - expectedFee;

        token.approve(user1, transferAmount);

        vm.prank(user1);
        token.transferFrom(owner, user2, transferAmount);

        assertEq(token.balanceOf(user2), expectedTransfer);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function testTransferWithMaximumFee() public {
        uint256 maxFee = token.MAX_FEE_BASIS_POINTS(); // 5%
        token.setTransferFee(maxFee);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * maxFee + 5000) / 10000; // 5% = 50 tokens
        uint256 expectedTransfer = transferAmount - expectedFee;

        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), expectedTransfer);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
    }

    function testTransferWithZeroFee() public {
        token.setTransferFee(0);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 transferAmount = 1000 * 10 ** 18;

        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function testTransferWithFeeSmallAmountRoundsUp() public {
        token.setTransferFee(100); // 1%
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 transferAmount = 99; // 99 wei
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000; // rounds up to 1 wei
        uint256 expectedTransfer = transferAmount - expectedFee;

        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), expectedTransfer);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(
            expectedFee,
            1,
            "small transfer should incur at least 1 wei fee with round-up"
        );
    }

    // Edge Cases
    function testTransferWithFeeMinting() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        // Minting should not charge fee (from == address(0))
        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance);
    }

    function testTransferWithFeeBurning() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 burnAmount = 1000 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        // Burning should NOT charge fee (to == address(0))
        // User expects to burn exactly burnAmount
        token.burn(burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance);
    }

    function testTransferToZeroAddressNoFee() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 burnAmount = 1000 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        // Transfer to address(0) should NOT charge fee (burning)
        token.transfer(address(0), burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance);
    }

    function testTransferWithFeeZeroAmount() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 initialFeeRecipientBalance = token.balanceOf(feeRecipient);

        // Zero amount transfer should not charge fee
        token.transfer(user1, 0);

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(feeRecipient), initialFeeRecipientBalance);
    }

    function testTransferWithFeeSelfTransfer() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;
        uint256 expectedTransfer = transferAmount - expectedFee;
        uint256 initialBalance = token.balanceOf(owner);

        // Self-transfer should still charge fee
        token.transfer(owner, transferAmount);

        assertEq(token.balanceOf(owner), initialBalance - expectedFee);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
    }

    function testTransferWithFeeRecipientAsReceiver() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;
        uint256 expectedTransfer = transferAmount - expectedFee;

        token.transfer(feeRecipient, transferAmount);

        // Fee recipient receives transfer amount minus fee, plus the fee
        assertEq(token.balanceOf(feeRecipient), expectedTransfer + expectedFee);
    }

    function testTransferWithFeeRecipientAsSender() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        // Give feeRecipient some tokens
        token.mint(feeRecipient, 1000 * 10 ** 18);

        uint256 transferAmount = 500 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;
        uint256 expectedTransfer = transferAmount - expectedFee;

        vm.prank(feeRecipient);
        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), expectedTransfer);
        assertEq(
            token.balanceOf(feeRecipient),
            1000 * 10 ** 18 - transferAmount
        );
    }

    function testTransferWithFeeNoRecipientSet() public {
        token.setTransferFee(100);
        token.setTransferFeeEnabled(true);
        // feeRecipient remains address(0)

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;
        uint256 expectedTransfer = transferAmount - expectedFee;
        uint256 initialSupply = token.totalSupply();

        // Fee should be explicitly burned when recipient is address(0)
        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), expectedTransfer);
        assertEq(token.totalSupply(), initialSupply - expectedFee); // Supply decreases by fee amount

        // Verify ERC20 invariant: totalSupply should equal sum of balances
        uint256 totalBalances = token.balanceOf(owner) + token.balanceOf(user1);
        assertEq(token.totalSupply(), totalBalances);
    }

    function testTransferWithFeeBurnedVotingPower() public {
        token.setTransferFee(100);
        token.setTransferFeeEnabled(true);
        // feeRecipient remains address(0) - fees will be burned

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;

        uint256 ownerVotesBefore = token.getVotes(owner);
        uint256 user1VotesBefore = token.getVotes(user1);

        token.transfer(user1, transferAmount);

        // Move blocks to update checkpoints
        vm.roll(block.number + 1);

        uint256 ownerVotesAfter = token.getVotes(owner);
        uint256 user1VotesAfter = token.getVotes(user1);

        // Owner's voting power should decrease by full amount (transfer + fee)
        assertEq(ownerVotesBefore - ownerVotesAfter, transferAmount);

        // User1's voting power should increase by transfer amount minus fee
        assertEq(
            user1VotesAfter - user1VotesBefore,
            transferAmount - expectedFee
        );

        // Fee was burned, so no one's voting power should increase by the fee
        // Total voting power should decrease by the fee amount (burned)
    }

    // Voting Power Tests
    function testVotingPowerWithFee() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;
        uint256 expectedTransfer = transferAmount - expectedFee;

        uint256 ownerVotesBefore = token.getVotes(owner);
        uint256 user1VotesBefore = token.getVotes(user1);
        uint256 feeRecipientVotesBefore = token.getVotes(feeRecipient);

        token.transfer(user1, transferAmount);

        // Move blocks to update checkpoints
        vm.roll(block.number + 1);

        uint256 ownerVotesAfter = token.getVotes(owner);
        uint256 user1VotesAfter = token.getVotes(user1);
        uint256 feeRecipientVotesAfter = token.getVotes(feeRecipient);

        // Owner's voting power should decrease by full amount (transfer + fee)
        assertEq(ownerVotesBefore - ownerVotesAfter, transferAmount);

        // User1's voting power should increase by transfer amount minus fee
        assertEq(user1VotesAfter - user1VotesBefore, expectedTransfer);

        // Fee recipient's voting power should increase by fee
        assertEq(feeRecipientVotesAfter - feeRecipientVotesBefore, expectedFee);
    }

    function testVotingPowerWithoutFee() public {
        token.setTransferFeeEnabled(false);

        uint256 transferAmount = 1000 * 10 ** 18;

        uint256 ownerVotesBefore = token.getVotes(owner);
        uint256 user1VotesBefore = token.getVotes(user1);

        token.transfer(user1, transferAmount);

        vm.roll(block.number + 1);

        uint256 ownerVotesAfter = token.getVotes(owner);
        uint256 user1VotesAfter = token.getVotes(user1);

        assertEq(ownerVotesBefore - ownerVotesAfter, transferAmount);
        assertEq(user1VotesAfter - user1VotesBefore, transferAmount);
    }

    // Integration Tests
    function testTransferFeeWithPause() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        token.pause();

        vm.expectRevert();
        token.transfer(user1, 1000 * 10 ** 18);
    }

    function testTransferFeeAfterUnpause() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        token.pause();
        token.unpause();

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;
        uint256 expectedTransfer = transferAmount - expectedFee;

        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), expectedTransfer);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
    }

    function testTransferFeeWithCappedSupply() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        // Fee should not affect cap checking
        uint256 remainingSupply = token.MAX_SUPPLY() - token.totalSupply();
        token.mint(user1, remainingSupply);

        assertEq(token.totalSupply(), token.MAX_SUPPLY());
    }

    // Fuzz Tests
    function testFuzzTransferWithFee(
        uint256 amount,
        uint256 feeBasisPoints
    ) public {
        feeBasisPoints = bound(feeBasisPoints, 0, token.MAX_FEE_BASIS_POINTS());
        amount = bound(amount, 1, token.balanceOf(owner) / 2); // Use at most half to avoid edge cases

        token.setTransferFee(feeBasisPoints);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 expectedFee = (amount * feeBasisPoints + 5000) / 10000;
        uint256 expectedTransfer = amount - expectedFee;

        token.transfer(user1, amount);

        assertEq(token.balanceOf(user1), expectedTransfer);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }

    // Gas Tests
    function testGasTransferWithFee() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);

        uint256 gasStart = gasleft();
        token.transfer(user1, 1000 * 10 ** 18);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for transfer with fee:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGasTransferWithoutFee() public {
        token.setTransferFeeEnabled(false);

        uint256 gasStart = gasleft();
        token.transfer(user1, 1000 * 10 ** 18);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for transfer without fee:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    // ============ Fee Exemption Tests ============

    function testSetFeeExemption() public {
        vm.expectEmit(true, false, false, true);
        emit FeeExemptionUpdated(dexPair, true);

        token.setFeeExemption(dexPair, true);
        assertTrue(token.isFeeExempt(dexPair));

        vm.expectEmit(true, false, false, true);
        emit FeeExemptionUpdated(dexPair, false);

        token.setFeeExemption(dexPair, false);
        assertFalse(token.isFeeExempt(dexPair));
    }

    function testSetFeeExemptionOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.setFeeExemption(dexPair, true);
    }

    function testSetFeeExemptionZeroAddress() public {
        vm.expectRevert("CPROToken: Invalid account");
        token.setFeeExemption(address(0), true);
    }

    function testTransferWithExemptSender() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);
        token.setFeeExemption(owner, true); // Owner is exempt

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        // Transfer from exempt address should not charge fee
        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(feeRecipient), feeRecipientBalanceBefore);
    }

    function testTransferWithExemptReceiver() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);
        token.setFeeExemption(user1, true); // User1 is exempt

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        // Transfer to exempt address should not charge fee
        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(feeRecipient), feeRecipientBalanceBefore);
    }

    function testTransferWithBothExempt() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);
        token.setFeeExemption(owner, true);
        token.setFeeExemption(user1, true);

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        // Transfer between exempt addresses should not charge fee
        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(feeRecipient), feeRecipientBalanceBefore);
    }

    function testTransferWithNonExemptPaysFee() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);
        // No exemptions set

        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 expectedFee = (transferAmount * 100 + 5000) / 10000;
        uint256 expectedTransfer = transferAmount - expectedFee;

        // Transfer between non-exempt addresses should charge fee
        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), expectedTransfer);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
    }

    function testBatchSetFeeExemptions() public {
        address[] memory accounts = new address[](3);
        bool[] memory exempts = new bool[](3);

        accounts[0] = dexPair;
        accounts[1] = stakingContract;
        accounts[2] = user1;

        exempts[0] = true;
        exempts[1] = true;
        exempts[2] = false;

        token.batchSetFeeExemptions(accounts, exempts);

        assertTrue(token.isFeeExempt(dexPair));
        assertTrue(token.isFeeExempt(stakingContract));
        assertFalse(token.isFeeExempt(user1));
    }

    function testBatchSetFeeExemptionsEmitsFeeExemptionSet() public {
        address[] memory accounts = new address[](2);
        bool[] memory exempts = new bool[](2);
        accounts[0] = dexPair;
        accounts[1] = user1;
        exempts[0] = true;
        exempts[1] = false;

        vm.expectEmit(false, false, false, true);
        emit FeeExemptionSet(accounts, exempts);
        token.batchSetFeeExemptions(accounts, exempts);
    }

    function testBatchSetFeeExemptionsOnlyOwner() public {
        address[] memory accounts = new address[](1);
        bool[] memory exempts = new bool[](1);
        accounts[0] = dexPair;
        exempts[0] = true;

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        token.batchSetFeeExemptions(accounts, exempts);
    }

    function testBatchSetFeeExemptionsLengthMismatch() public {
        address[] memory accounts = new address[](2);
        bool[] memory exempts = new bool[](1);
        accounts[0] = dexPair;
        accounts[1] = stakingContract;
        exempts[0] = true;

        vm.expectRevert("CPROToken: Arrays length mismatch");
        token.batchSetFeeExemptions(accounts, exempts);
    }

    function testBatchSetFeeExemptionsEmptyArrays() public {
        address[] memory accounts = new address[](0);
        bool[] memory exempts = new bool[](0);

        vm.expectRevert("CPROToken: Empty arrays");
        token.batchSetFeeExemptions(accounts, exempts);
    }

    function testBatchSetFeeExemptionsZeroAddress() public {
        address[] memory accounts = new address[](1);
        bool[] memory exempts = new bool[](1);
        accounts[0] = address(0);
        exempts[0] = true;

        vm.expectRevert("CPROToken: Invalid account");
        token.batchSetFeeExemptions(accounts, exempts);
    }

    function testExemptAddressVotingPower() public {
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);
        token.setFeeExemption(dexPair, true);

        // Give dexPair some tokens
        token.mint(dexPair, 1000 * 10 ** 18);

        uint256 transferAmount = 500 * 10 ** 18;
        uint256 dexPairVotesBefore = token.getVotes(dexPair);
        uint256 user1VotesBefore = token.getVotes(user1);

        vm.prank(dexPair);
        token.transfer(user1, transferAmount);

        vm.roll(block.number + 1);

        uint256 dexPairVotesAfter = token.getVotes(dexPair);
        uint256 user1VotesAfter = token.getVotes(user1);

        // No fee, so voting power should change by full amount
        assertEq(dexPairVotesBefore - dexPairVotesAfter, transferAmount);
        assertEq(user1VotesAfter - user1VotesBefore, transferAmount);
    }

    function testDexPairScenario() public {
        // Simulate DEX pair interaction
        token.setTransferFee(100);
        token.setFeeRecipient(feeRecipient);
        token.setTransferFeeEnabled(true);
        token.setFeeExemption(dexPair, true);

        // User transfers to DEX pair (no fee)
        uint256 amount1 = 1000 * 10 ** 18;
        token.transfer(dexPair, amount1);
        assertEq(token.balanceOf(dexPair), amount1);

        // DEX pair transfers to user (no fee)
        vm.prank(dexPair);
        token.transfer(user1, amount1);
        assertEq(token.balanceOf(user1), amount1);
        assertEq(token.balanceOf(feeRecipient), 0);
    }
}
