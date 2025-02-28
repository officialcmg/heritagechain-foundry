// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title HeritageChain
 * @author officialcmg
 * @notice A Digital Legacy Manager smart contract that automates the distribution of digital assets
 * based on time-based triggers or voluntary activation by the originator
 */
contract HeritageChain is Ownable, ReentrancyGuard {
    using Address for address payable;

    // Asset types supported by the contract
    enum AssetType { ETH, ERC20, ERC721 }

    // Trigger types for asset distribution
    enum TriggerType { NONE, TIME_BASED, VOLUNTARY }

    // Structure to represent a digital asset
    struct Asset {
        AssetType assetType;
        address contractAddress; // Zero address for ETH
        uint256 amount; // For ETH and ERC20, amount is the value. For ERC721, amount is the token ID
        uint256 depositTimestamp;
    }

    // Structure to represent a beneficiary
    struct Beneficiary {
        address beneficiaryAddress;
        uint256 sharePercentage; // Represented as basis points (1% = 100)
    }

    // Structure to store trigger information
    struct Trigger {
        TriggerType triggerType;
        uint256 timestamp; // Only relevant for TIME_BASED
        bool isActivated;
    }

    // Contract state variables
    Asset[] public assets;
    Beneficiary[] public beneficiaries;
    Trigger public trigger;
    bool public isDistributed;
    uint256 public totalETHDeposited;
    
    // Constants
    uint256 constant BASIS_POINTS = 10000; // 100% in basis points

    // Events for audit logging
    event AssetDeposited(uint256 indexed assetId, AssetType assetType, address indexed contractAddress, uint256 amount, uint256 timestamp);
    event BeneficiaryAdded(address indexed beneficiaryAddress, uint256 sharePercentage);
    event BeneficiariesConfigured(uint256 beneficiaryCount);
    event TriggerSet(TriggerType triggerType, uint256 timestamp);
    event TriggerActivated(uint256 timestamp);
    event DistributionExecuted(uint256 timestamp);
    event LegacyPlanCancelled(uint256 timestamp);
    event ETHWithdrawn(address indexed recipient, uint256 amount);
    event ERC20Withdrawn(address indexed recipient, address indexed tokenContract, uint256 amount);
    event ERC721Withdrawn(address indexed recipient, address indexed tokenContract, uint256 tokenId);

    /**
     * @dev Constructor that sets the originator as the owner
     */
    constructor(address _owner) Ownable(_owner) {
        // Initialize with no trigger
        trigger = Trigger({
            triggerType: TriggerType.NONE,
            timestamp: 0,
            isActivated: false
        });
    }

    /**
     * @notice Allows the originator to deposit ETH into the contract
     */
    function depositETH() external payable onlyOwner {
        require(msg.value > 0, "Amount must be greater than 0");
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.NONE || !trigger.isActivated, "Trigger already activated");

        // Create and store the asset
        uint256 assetId = assets.length;
        assets.push(Asset({
            assetType: AssetType.ETH,
            contractAddress: address(0),
            amount: msg.value,
            depositTimestamp: block.timestamp
        }));

        totalETHDeposited += msg.value;

        // Emit asset deposited event
        emit AssetDeposited(assetId, AssetType.ETH, address(0), msg.value, block.timestamp);
    }

    /**
     * @notice Allows the originator to deposit ERC20 tokens into the contract
     * @param tokenContract Address of the ERC20 token contract
     * @param amount Amount of tokens to deposit
     */
    function depositERC20(address tokenContract, uint256 amount) external onlyOwner {
        require(tokenContract != address(0), "Invalid token contract address");
        require(amount > 0, "Amount must be greater than 0");
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.NONE || !trigger.isActivated, "Trigger already activated");

        // Transfer tokens from originator to this contract
        IERC20 token = IERC20(tokenContract);
        uint256 beforeBalance = token.balanceOf(address(this));
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        
        // Verify the transfer was successful by checking balance change
        uint256 afterBalance = token.balanceOf(address(this));
        require(afterBalance >= beforeBalance + amount, "Token transfer verification failed");

        // Create and store the asset
        uint256 assetId = assets.length;
        assets.push(Asset({
            assetType: AssetType.ERC20,
            contractAddress: tokenContract,
            amount: amount,
            depositTimestamp: block.timestamp
        }));

        // Emit asset deposited event
        emit AssetDeposited(assetId, AssetType.ERC20, tokenContract, amount, block.timestamp);
    }

    /**
     * @notice Allows the originator to deposit an ERC721 token (NFT) into the contract
     * @param tokenContract Address of the ERC721 token contract
     * @param tokenId ID of the NFT to deposit
     */
    function depositERC721(address tokenContract, uint256 tokenId) external onlyOwner {
        require(tokenContract != address(0), "Invalid token contract address");
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.NONE || !trigger.isActivated, "Trigger already activated");

        // Transfer NFT from originator to this contract
        IERC721 nft = IERC721(tokenContract);
        nft.transferFrom(msg.sender, address(this), tokenId);
        
        // Verify the transfer was successful
        require(nft.ownerOf(tokenId) == address(this), "NFT transfer failed");

        // Create and store the asset
        uint256 assetId = assets.length;
        assets.push(Asset({
            assetType: AssetType.ERC721,
            contractAddress: tokenContract,
            amount: tokenId,  // For ERC721, amount stores the token ID
            depositTimestamp: block.timestamp
        }));

        // Emit asset deposited event
        emit AssetDeposited(assetId, AssetType.ERC721, tokenContract, tokenId, block.timestamp);
    }

    /**
     * @notice Allows the originator to configure beneficiaries and their share percentages
     * @param _beneficiaryAddresses Array of beneficiary addresses
     * @param _sharePercentages Array of share percentages in basis points (100% = 10000)
     */
    function configureBeneficiaries(
        address[] calldata _beneficiaryAddresses,
        uint256[] calldata _sharePercentages
    ) external onlyOwner {
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.NONE || !trigger.isActivated, "Trigger already activated");
        require(_beneficiaryAddresses.length > 0, "Must have at least one beneficiary");
        require(_beneficiaryAddresses.length == _sharePercentages.length, "Arrays length mismatch");

        // Clear existing beneficiaries
        delete beneficiaries;

        // Calculate sum of percentages to ensure they equal 100%
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _sharePercentages.length; i++) {
            require(_beneficiaryAddresses[i] != address(0), "Invalid beneficiary address");
            require(_sharePercentages[i] > 0, "Share percentage must be greater than 0");
            
            totalPercentage += _sharePercentages[i];
            
            // Add the beneficiary
            beneficiaries.push(Beneficiary({
                beneficiaryAddress: _beneficiaryAddresses[i],
                sharePercentage: _sharePercentages[i]
            }));
            
            emit BeneficiaryAdded(_beneficiaryAddresses[i], _sharePercentages[i]);
        }
        
        require(totalPercentage == BASIS_POINTS, "Total percentage must equal 100%");
        
        emit BeneficiariesConfigured(beneficiaries.length);
    }

    /**
     * @notice Allows the originator to set a time-based trigger
     * @param _timestamp UNIX timestamp when the distribution should occur
     */
    function setTimeTrigger(uint256 _timestamp) external onlyOwner {
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.NONE || !trigger.isActivated, "Trigger already activated");
        require(_timestamp > block.timestamp, "Timestamp must be in the future");
        require(beneficiaries.length > 0, "Beneficiaries must be configured first");
        
        trigger = Trigger({
            triggerType: TriggerType.TIME_BASED,
            timestamp: _timestamp,
            isActivated: false
        });
        
        emit TriggerSet(TriggerType.TIME_BASED, _timestamp);
    }

    /**
     * @notice Allows the originator to set a voluntary activation trigger
     */
    function setVoluntaryTrigger() external onlyOwner {
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.NONE || !trigger.isActivated, "Trigger already activated");
        require(beneficiaries.length > 0, "Beneficiaries must be configured first");
        
        trigger = Trigger({
            triggerType: TriggerType.VOLUNTARY,
            timestamp: 0,
            isActivated: false
        });
        
        emit TriggerSet(TriggerType.VOLUNTARY, 0);
    }

    /**
     * @notice Allows the originator to voluntarily activate the distribution
     */
    function activateVoluntaryTrigger() external onlyOwner {
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.VOLUNTARY, "Trigger is not voluntary");
        require(!trigger.isActivated, "Trigger already activated");
        
        trigger.isActivated = true;
        emit TriggerActivated(block.timestamp);
        
        // Execute distribution
        _executeDistribution();
    }

    /**
     * @notice Checks if the time-based trigger should be activated and executes distribution if needed
     * This function can be called by anyone to check if the time-based trigger condition is met
     */
    function checkTimeBasedTrigger() external {
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.TIME_BASED, "Trigger is not time-based");
        require(!trigger.isActivated, "Trigger already activated");
        require(block.timestamp >= trigger.timestamp, "Trigger time not reached");
        
        trigger.isActivated = true;
        emit TriggerActivated(block.timestamp);
        
        // Execute distribution
        _executeDistribution();
    }

    /**
     * @notice Allows the originator to cancel the legacy plan and withdraw all assets
     */
    function cancelLegacyPlan() external onlyOwner nonReentrant {
        require(!isDistributed, "Assets already distributed");
        require(trigger.triggerType == TriggerType.NONE || !trigger.isActivated, "Trigger already activated");
        
        isDistributed = true; // Mark as distributed to prevent double cancellation
        
        // Return all assets to the originator
        _returnAllAssetsToOwner();
        
        // Reset trigger
        trigger = Trigger({
            triggerType: TriggerType.NONE,
            timestamp: 0,
            isActivated: false
        });
        
        emit LegacyPlanCancelled(block.timestamp);
    }

    /**
     * @notice Returns true if funds have been distributed and false otherwise
     * @return Boolean for the state of ditribution 
     */
    function getIsDistributed() external view returns (bool) {
        return isDistributed;
    }

    /**
     * @notice Returns the number of assets stored in the contract
     * @return The count of assets
     */
    function getAssetCount() external view returns (uint256) {
        return assets.length;
    }

    /**
     * @notice Returns the number of beneficiaries configured
     * @return The count of beneficiaries
     */
    function getBeneficiaryCount() external view returns (uint256) {
        return beneficiaries.length;
    }

    /**
     * @notice Internal function to execute the distribution of assets to beneficiaries
     */
    function _executeDistribution() internal nonReentrant {
        require(!isDistributed, "Assets already distributed");
        require(beneficiaries.length > 0, "No beneficiaries configured");
        require(assets.length > 0, "No assets to distribute");
        
        isDistributed = true;
        
        // Distribute each asset according to beneficiary percentages
        for (uint256 i = 0; i < assets.length; i++) {
            Asset storage asset = assets[i];
            
            if (asset.assetType == AssetType.ETH) {
                _distributeETH(asset);
            } else if (asset.assetType == AssetType.ERC20) {
                _distributeERC20(asset);
            } else if (asset.assetType == AssetType.ERC721) {
                _distributeERC721(asset);
            }
        }
        
        emit DistributionExecuted(block.timestamp);
    }

    /**
     * @notice Distributes ETH to beneficiaries according to their percentages
     * @param asset The ETH asset to distribute
     */
    function _distributeETH(Asset storage asset) internal {
        require(asset.assetType == AssetType.ETH, "Not an ETH asset");
        
        // For each beneficiary, calculate and transfer their share
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            Beneficiary storage beneficiary = beneficiaries[i];
            
            // Calculate share amount based on percentage
            uint256 shareAmount = (asset.amount * beneficiary.sharePercentage) / BASIS_POINTS;
            
            if (shareAmount > 0) {
                // Transfer ETH to beneficiary
                payable(beneficiary.beneficiaryAddress).sendValue(shareAmount);
                emit ETHWithdrawn(beneficiary.beneficiaryAddress, shareAmount);
            }
        }
    }

    /**
     * @notice Distributes ERC20 tokens to beneficiaries according to their percentages
     * @param asset The ERC20 asset to distribute
     */
    function _distributeERC20(Asset storage asset) internal {
        require(asset.assetType == AssetType.ERC20, "Not an ERC20 asset");
        
        IERC20 token = IERC20(asset.contractAddress);
        
        // For each beneficiary, calculate and transfer their share
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            Beneficiary storage beneficiary = beneficiaries[i];
            
            // Calculate share amount based on percentage
            uint256 shareAmount = (asset.amount * beneficiary.sharePercentage) / BASIS_POINTS;
            
            if (shareAmount > 0) {
                // Transfer tokens to beneficiary
                bool success = token.transfer(beneficiary.beneficiaryAddress, shareAmount);
                require(success, "ERC20 transfer failed");
                emit ERC20Withdrawn(beneficiary.beneficiaryAddress, asset.contractAddress, shareAmount);
            }
        }
    }

    /**
     * @notice Distributes an ERC721 token (NFT) to a beneficiary
     * @param asset The ERC721 asset to distribute
     */
    function _distributeERC721(Asset storage asset) internal {
        require(asset.assetType == AssetType.ERC721, "Not an ERC721 asset");
        
        // NFTs are indivisible, so we assign to the beneficiary with the highest percentage
        uint256 highestPercentage = 0;
        address recipient = address(0);
        
        // Find beneficiary with highest percentage
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i].sharePercentage > highestPercentage) {
                highestPercentage = beneficiaries[i].sharePercentage;
                recipient = beneficiaries[i].beneficiaryAddress;
            }
        }
        
        // Transfer the NFT to the chosen beneficiary
        IERC721 nft = IERC721(asset.contractAddress);
        nft.transferFrom(address(this), recipient, asset.amount);
        emit ERC721Withdrawn(recipient, asset.contractAddress, asset.amount);
    }

    /**
     * @notice Returns all assets to the contract owner when cancelling the legacy plan
     */
    function _returnAllAssetsToOwner() internal {
        address payable ownerAddress = payable(owner());
        
        // Return each asset to the owner
        for (uint256 i = 0; i < assets.length; i++) {
            Asset storage asset = assets[i];
            
            if (asset.assetType == AssetType.ETH) {
                // Return ETH
                ownerAddress.sendValue(asset.amount);
                emit ETHWithdrawn(ownerAddress, asset.amount);
            } else if (asset.assetType == AssetType.ERC20) {
                // Return ERC20 tokens
                IERC20 token = IERC20(asset.contractAddress);
                bool success = token.transfer(ownerAddress, asset.amount);
                require(success, "ERC20 transfer failed");
                emit ERC20Withdrawn(ownerAddress, asset.contractAddress, asset.amount);
            } else if (asset.assetType == AssetType.ERC721) {
                // Return NFT
                IERC721 nft = IERC721(asset.contractAddress);
                nft.transferFrom(address(this), ownerAddress, asset.amount);
                emit ERC721Withdrawn(ownerAddress, asset.contractAddress, asset.amount);
            }
        }
    }

    /**
     * @notice Fallback function to accept ETH transfers
     */
    receive() external payable {
        // Only the owner can send ETH directly
        if (msg.sender != owner()) {
            revert("Direct ETH transfers only allowed from owner");
        }
        
        // Create and store the asset
        uint256 assetId = assets.length;
        assets.push(Asset({
            assetType: AssetType.ETH,
            contractAddress: address(0),
            amount: msg.value,
            depositTimestamp: block.timestamp
        }));

        totalETHDeposited += msg.value;
        
        // Emit asset deposited event
        emit AssetDeposited(assetId, AssetType.ETH, address(0), msg.value, block.timestamp);
    }
}