// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { HeritageChain } from "../src/HeritageChain.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";


contract MockERC20 is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor() ERC20("Mock Token", "MTK") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}

contract MockERC721 is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 private _tokenIdCounter;

    constructor() ERC721("Mock NFT", "MNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function mint(address to) public onlyRole(MINTER_ROLE) {
        _mint(to, _tokenIdCounter);
        _tokenIdCounter++;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}


contract HeritageChainTest is Test {
    HeritageChain public heritageChain;
    MockERC20 public mockERC20;
    MockERC721 public mockERC721;
    
    address public originator;
    address public beneficiary1;
    address public beneficiary2;
    address public beneficiary3;
    
    uint256 constant BASIS_POINTS = 10000;

    function setUp() public {
        // Create test accounts
        originator = address(1);
        beneficiary1 = address(2);
        beneficiary2 = address(3);
        beneficiary3 = address(4);
        
        // Deploy mock tokens
        mockERC20 = new MockERC20();
        mockERC721 = new MockERC721();

        // Grant MINTER_ROLE to originator
        mockERC20.grantRole(mockERC20.MINTER_ROLE(), originator);
        mockERC721.grantRole(mockERC721.MINTER_ROLE(), originator);
        
        // Set up originator with tokens
        vm.startPrank(originator);
        
        // Deploy HeritageChain contract
        heritageChain = new HeritageChain(originator);
        
        // Mint test tokens to originator
        mockERC20.mint(originator, 1000 ether);
        
        // Mint NFTs to originator
        mockERC721.mint(originator);  // TokenId 0
        mockERC721.mint(originator);  // TokenId 1
        
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////
    // Helper Functions
    //////////////////////////////////////////////////////////////
    
    function _setupBasicLegacyPlan() internal {
        vm.startPrank(originator);

        // Deal ETH to originator first
        vm.deal(originator, 100 ether);
        
        // Deposit ETH
        heritageChain.depositETH{value: 10 ether}();
        
        // Deposit ERC20
        mockERC20.approve(address(heritageChain), 100 ether);
        heritageChain.depositERC20(address(mockERC20), 100 ether);
        
        // Deposit ERC721
        mockERC721.approve(address(heritageChain), 0);
        heritageChain.depositERC721(address(mockERC721), 0);
        
        // Configure beneficiaries (60%, 40%)
        address[] memory addresses = new address[](2);
        addresses[0] = beneficiary1;
        addresses[1] = beneficiary2;
        
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 6000;  // 60%
        percentages[1] = 4000;  // 40%
        
        heritageChain.configureBeneficiaries(addresses, percentages);
        
        vm.stopPrank();
    }

    function _advanceTime(uint256 seconds_) internal {
        // Advance the blockchain time
        vm.warp(block.timestamp + seconds_);
        // Mine a new block with the new timestamp
        vm.roll(block.number + 1);
    }

    //////////////////////////////////////////////////////////////
    // Test Cases for ETH Deposits
    //////////////////////////////////////////////////////////////
    
    function testDepositETH() public {
        vm.startPrank(originator);
        vm.deal(originator, 10 ether);
        
        // Deposit ETH
        heritageChain.depositETH{value: 5 ether}();
        
        // Verify the contract state
        assertEq(address(heritageChain).balance, 5 ether);
        assertEq(heritageChain.totalETHDeposited(), 5 ether);
        assertEq(heritageChain.getAssetCount(), 1);
        
        // Verify the asset details
        (HeritageChain.AssetType assetType, address contractAddress, uint256 amount, ) = heritageChain.assets(0);
        assertEq(uint(assetType), uint(HeritageChain.AssetType.ETH));
        assertEq(contractAddress, address(0));
        assertEq(amount, 5 ether);
        
        vm.stopPrank();
    }
    
    function testDepositETHViaFallback() public {
        vm.startPrank(originator);
        vm.deal(originator, 10 ether);
        
        // Send ETH directly to the contract
        (bool success, ) = address(heritageChain).call{value: 3 ether}("");
        assertTrue(success);
        
        // Verify the contract state
        assertEq(address(heritageChain).balance, 3 ether);
        assertEq(heritageChain.totalETHDeposited(), 3 ether);
        assertEq(heritageChain.getAssetCount(), 1);
        
        vm.stopPrank();
    }
    
    function testFailDepositETHFromNonOwner() public {
        vm.startPrank(beneficiary1);
        vm.deal(beneficiary1, 10 ether);
        
        // Try to deposit ETH from non-owner (should fail)
        heritageChain.depositETH{value: 5 ether}();
        
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////
    // Test Cases for ERC20 Deposits
    //////////////////////////////////////////////////////////////
    
    function testDepositERC20() public {
        vm.startPrank(originator);
        
        // Approve and deposit ERC20 tokens
        mockERC20.approve(address(heritageChain), 100 ether);
        heritageChain.depositERC20(address(mockERC20), 100 ether);
        
        // Verify the contract state
        assertEq(mockERC20.balanceOf(address(heritageChain)), 100 ether);
        assertEq(heritageChain.getAssetCount(), 1);
        
        // Verify the asset details
        (HeritageChain.AssetType assetType, address contractAddress, uint256 amount, ) = heritageChain.assets(0);
        assertEq(uint(assetType), uint(HeritageChain.AssetType.ERC20));
        assertEq(contractAddress, address(mockERC20));
        assertEq(amount, 100 ether);
        
        vm.stopPrank();
    }
    
    function testFailDepositERC20WithoutApproval() public {
        vm.startPrank(originator);
        
        // Try to deposit ERC20 tokens without approval (should fail)
        heritageChain.depositERC20(address(mockERC20), 100 ether);
        
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////
    // Test Cases for ERC721 Deposits
    //////////////////////////////////////////////////////////////
    
    function testDepositERC721() public {
        vm.startPrank(originator);
        
        // Approve and deposit ERC721 token
        mockERC721.approve(address(heritageChain), 0);
        heritageChain.depositERC721(address(mockERC721), 0);
        
        // Verify the contract state
        assertEq(mockERC721.ownerOf(0), address(heritageChain));
        assertEq(heritageChain.getAssetCount(), 1);
        
        // Verify the asset details
        (HeritageChain.AssetType assetType, address contractAddress, uint256 amount, ) = heritageChain.assets(0);
        assertEq(uint(assetType), uint(HeritageChain.AssetType.ERC721));
        assertEq(contractAddress, address(mockERC721));
        assertEq(amount, 0);  // Token ID
        
        vm.stopPrank();
    }
    
    function testFailDepositERC721WithoutApproval() public {
        vm.startPrank(originator);
        
        // Try to deposit ERC721 token without approval (should fail)
        heritageChain.depositERC721(address(mockERC721), 0);
        
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////
    // Test Cases for Beneficiary Configuration
    //////////////////////////////////////////////////////////////
    
    function testConfigureBeneficiaries() public {
        vm.startPrank(originator);
        
        // Configure beneficiaries
        address[] memory addresses = new address[](3);
        addresses[0] = beneficiary1;
        addresses[1] = beneficiary2;
        addresses[2] = beneficiary3;
        
        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000;  // 50%
        percentages[1] = 3000;  // 30%
        percentages[2] = 2000;  // 20%
        
        heritageChain.configureBeneficiaries(addresses, percentages);
        
        // Verify the contract state
        assertEq(heritageChain.getBeneficiaryCount(), 3);
        
        // Verify the beneficiary details
        (address benAddress1, uint256 sharePercentage1) = heritageChain.beneficiaries(0);
        assertEq(benAddress1, beneficiary1);
        assertEq(sharePercentage1, 5000);
        
        (address benAddress2, uint256 sharePercentage2) = heritageChain.beneficiaries(1);
        assertEq(benAddress2, beneficiary2);
        assertEq(sharePercentage2, 3000);
        
        (address benAddress3, uint256 sharePercentage3) = heritageChain.beneficiaries(2);
        assertEq(benAddress3, beneficiary3);
        assertEq(sharePercentage3, 2000);
        
        vm.stopPrank();
    }
    
    function testFailConfigureBeneficiariesWithInvalidTotal() public {
        vm.startPrank(originator);
        
        // Configure beneficiaries with total not equal to 100%
        address[] memory addresses = new address[](2);
        addresses[0] = beneficiary1;
        addresses[1] = beneficiary2;
        
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 5000;  // 50%
        percentages[1] = 4000;  // 40% (total 90%, should fail)
        
        heritageChain.configureBeneficiaries(addresses, percentages);
        
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////
    // Test Cases for Trigger Setting and Activation
    //////////////////////////////////////////////////////////////
    
    function testSetTimeTrigger() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set time-based trigger for 30 days later
        uint256 triggerTime = block.timestamp + 30 days;
        heritageChain.setTimeTrigger(triggerTime);
        
        // Verify the trigger details
        (HeritageChain.TriggerType triggerType, uint256 timestamp, bool isActivated) = heritageChain.trigger();
        assertEq(uint(triggerType), uint(HeritageChain.TriggerType.TIME_BASED));
        assertEq(timestamp, triggerTime);
        assertEq(isActivated, false);
        
        vm.stopPrank();
    }
    
    function testSetVoluntaryTrigger() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set voluntary trigger
        heritageChain.setVoluntaryTrigger();
        
        // Verify the trigger details
        (HeritageChain.TriggerType triggerType, uint256 timestamp, bool isActivated) = heritageChain.trigger();
        assertEq(uint(triggerType), uint(HeritageChain.TriggerType.VOLUNTARY));
        assertEq(timestamp, 0);
        assertEq(isActivated, false);
        
        vm.stopPrank();
    }
    
    function testActivateVoluntaryTrigger() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set up initial balances for verification
        vm.deal(beneficiary1, 0);
        vm.deal(beneficiary2, 0);
        uint256 initialERC20Balance1 = mockERC20.balanceOf(beneficiary1);
        uint256 initialERC20Balance2 = mockERC20.balanceOf(beneficiary2);
        
        // Set voluntary trigger and activate it
        heritageChain.setVoluntaryTrigger();
        heritageChain.activateVoluntaryTrigger();
        
        // Verify the trigger details
        (HeritageChain.TriggerType triggerType, uint256 timestamp, bool isActivated) = heritageChain.trigger();
        assertEq(uint(triggerType), uint(HeritageChain.TriggerType.VOLUNTARY));
        assertEq(isActivated, true);
        
        // Verify the distribution has occurred
        assertEq(heritageChain.isDistributed(), true);
        
        // Verify ETH distribution
        assertEq(beneficiary1.balance, 6 ether);  // 60% of 10 ETH
        assertEq(beneficiary2.balance, 4 ether);  // 40% of 10 ETH
        
        // Verify ERC20 distribution
        assertEq(mockERC20.balanceOf(beneficiary1), initialERC20Balance1 + 60 ether);  // 60% of 100 tokens
        assertEq(mockERC20.balanceOf(beneficiary2), initialERC20Balance2 + 40 ether);  // 40% of 100 tokens
        
        // Verify ERC721 distribution
        assertEq(mockERC721.ownerOf(0), beneficiary1);  // NFT goes to beneficiary with highest percentage
        
        vm.stopPrank();
    }
    
    function testCheckTimeBasedTrigger() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set up initial balances for verification
        vm.deal(beneficiary1, 0);
        vm.deal(beneficiary2, 0);
        uint256 initialERC20Balance1 = mockERC20.balanceOf(beneficiary1);
        uint256 initialERC20Balance2 = mockERC20.balanceOf(beneficiary2);
        
        // Set time-based trigger for 30 days later
        uint256 triggerTime = block.timestamp + 30 days;
        heritageChain.setTimeTrigger(triggerTime);
        
        vm.stopPrank();
        
        // Advance time past the trigger time
        _advanceTime(31 days);
        
        // Anyone can check the time-based trigger
        vm.prank(address(5));
        heritageChain.checkTimeBasedTrigger();
        
        // Verify the trigger details
        (HeritageChain.TriggerType triggerType, uint256 timestamp, bool isActivated) = heritageChain.trigger();
        assertEq(uint(triggerType), uint(HeritageChain.TriggerType.TIME_BASED));
        assertEq(isActivated, true);
        
        // Verify the distribution has occurred
        assertEq(heritageChain.isDistributed(), true);
        
        // Verify ETH distribution
        assertEq(beneficiary1.balance, 6 ether);  // 60% of 10 ETH
        assertEq(beneficiary2.balance, 4 ether);  // 40% of 10 ETH
        
        // Verify ERC20 distribution
        assertEq(mockERC20.balanceOf(beneficiary1), initialERC20Balance1 + 60 ether);  // 60% of 100 tokens
        assertEq(mockERC20.balanceOf(beneficiary2), initialERC20Balance2 + 40 ether);  // 40% of 100 tokens
        
        // Verify ERC721 distribution
        assertEq(mockERC721.ownerOf(0), beneficiary1);  // NFT goes to beneficiary with highest percentage
    }
    
    function testFailCheckTimeBasedTriggerTooEarly() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set time-based trigger for 30 days later
        uint256 triggerTime = block.timestamp + 30 days;
        heritageChain.setTimeTrigger(triggerTime);
        
        vm.stopPrank();
        
        // Advance time, but not past the trigger time
        _advanceTime(20 days);
        
        // This should fail because the trigger time hasn't been reached
        heritageChain.checkTimeBasedTrigger();
    }

    //////////////////////////////////////////////////////////////
    // Test Cases for Cancel Legacy Plan
    //////////////////////////////////////////////////////////////
    
    function testCancelLegacyPlan() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Record initial balances
        uint256 initialETHBalance = originator.balance;
        uint256 initialERC20Balance = mockERC20.balanceOf(originator);
        
        // Cancel the legacy plan
        heritageChain.cancelLegacyPlan();
        
        // Verify the contract state
        assertEq(heritageChain.isDistributed(), true);
        
        // Verify assets returned to owner
        assertEq(originator.balance, initialETHBalance + 10 ether);
        assertEq(mockERC20.balanceOf(originator), initialERC20Balance + 100 ether);
        assertEq(mockERC721.ownerOf(0), originator);
        
        // Verify the trigger was reset
        (HeritageChain.TriggerType triggerType, uint256 timestamp, bool isActivated) = heritageChain.trigger();
        assertEq(uint(triggerType), uint(HeritageChain.TriggerType.NONE));
        assertEq(timestamp, 0);
        assertEq(isActivated, false);
        
        vm.stopPrank();
    }
    
    function testFailCancelLegacyPlanAfterDistribution() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set voluntary trigger and activate it
        heritageChain.setVoluntaryTrigger();
        heritageChain.activateVoluntaryTrigger();
        
        // Try to cancel after distribution (should fail)
        heritageChain.cancelLegacyPlan();
        
        vm.stopPrank();
    }
    
    function testFailCancelLegacyPlanFromNonOwner() public {
        _setupBasicLegacyPlan();
        
        // Try to cancel from non-owner (should fail)
        vm.prank(beneficiary1);
        heritageChain.cancelLegacyPlan();
    }

    //////////////////////////////////////////////////////////////
    // Edge Cases and Additional Tests
    //////////////////////////////////////////////////////////////
    
    function testMultipleAssetTypes() public {
        vm.startPrank(originator);
        vm.deal(originator, 10 ether);
        
        // Deposit ETH
        heritageChain.depositETH{value: 5 ether}();
        
        // Deposit ERC20
        mockERC20.approve(address(heritageChain), 50 ether);
        heritageChain.depositERC20(address(mockERC20), 50 ether);
        
        // Deposit another ERC20 amount
        mockERC20.approve(address(heritageChain), 30 ether);
        heritageChain.depositERC20(address(mockERC20), 30 ether);
        
        // Deposit ERC721
        mockERC721.approve(address(heritageChain), 0);
        heritageChain.depositERC721(address(mockERC721), 0);
        
        // Deposit another ERC721
        mockERC721.approve(address(heritageChain), 1);
        heritageChain.depositERC721(address(mockERC721), 1);
        
        // Verify the asset count
        assertEq(heritageChain.getAssetCount(), 5);
        
        vm.stopPrank();
    }
    
    function testFailDepositAfterTriggerActivation() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set voluntary trigger and activate it
        heritageChain.setVoluntaryTrigger();
        heritageChain.activateVoluntaryTrigger();
        
        // Try to deposit more ETH after activation (should fail)
        heritageChain.depositETH{value: 5 ether}();
        
        vm.stopPrank();
    }
    
    function testUpdateBeneficiaries() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Update beneficiary configuration
        address[] memory newAddresses = new address[](2);
        newAddresses[0] = beneficiary2;
        newAddresses[1] = beneficiary3;
        
        uint256[] memory newPercentages = new uint256[](2);
        newPercentages[0] = 7000;  // 70%
        newPercentages[1] = 3000;  // 30%
        
        heritageChain.configureBeneficiaries(newAddresses, newPercentages);
        
        // Verify updated configuration
        assertEq(heritageChain.getBeneficiaryCount(), 2);
        
        (address benAddress1, uint256 sharePercentage1) = heritageChain.beneficiaries(0);
        assertEq(benAddress1, beneficiary2);
        assertEq(sharePercentage1, 7000);
        
        (address benAddress2, uint256 sharePercentage2) = heritageChain.beneficiaries(1);
        assertEq(benAddress2, beneficiary3);
        assertEq(sharePercentage2, 3000);
        
        vm.stopPrank();
    }
    
    function testFailUpdateBeneficiariesAfterTriggerActivation() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set voluntary trigger and activate it
        heritageChain.setVoluntaryTrigger();
        heritageChain.activateVoluntaryTrigger();
        
        // Try to update beneficiaries after activation (should fail)
        address[] memory newAddresses = new address[](2);
        newAddresses[0] = beneficiary2;
        newAddresses[1] = beneficiary3;
        
        uint256[] memory newPercentages = new uint256[](2);
        newPercentages[0] = 7000;
        newPercentages[1] = 3000;
        
        heritageChain.configureBeneficiaries(newAddresses, newPercentages);
        
        vm.stopPrank();
    }
    
    function testChangeTriggerType() public {
        _setupBasicLegacyPlan();
        
        vm.startPrank(originator);
        
        // Set time-based trigger
        uint256 triggerTime = block.timestamp + 30 days;
        heritageChain.setTimeTrigger(triggerTime);
        
        // Change to voluntary trigger
        heritageChain.setVoluntaryTrigger();
        
        // Verify the trigger was changed
        (HeritageChain.TriggerType triggerType, uint256 timestamp, bool isActivated) = heritageChain.trigger();
        assertEq(uint(triggerType), uint(HeritageChain.TriggerType.VOLUNTARY));
        assertEq(timestamp, 0);
        assertEq(isActivated, false);
        
        vm.stopPrank();
    }
    
    function testFailSetTriggerWithoutBeneficiaries() public {
        vm.startPrank(originator);
        vm.deal(originator, 10 ether);
        
        // Deposit ETH
        heritageChain.depositETH{value: 5 ether}();
        
        // Try to set trigger without configuring beneficiaries (should fail)
        heritageChain.setVoluntaryTrigger();
        
        vm.stopPrank();
    }
}
