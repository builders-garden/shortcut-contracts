// SPDX-License-Identifier: MIT 
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

pragma solidity ^0.8.24;

contract ActionCampaigns is ERC1155, Ownable, ERC1155Supply, AutomationCompatibleInterface {

    //║══════════════════════════════════════════╗
    //║              Events                      ║
    //║══════════════════════════════════════════╝
    event CampaignHasEnded(uint256 campaignId);
    event WithdrawFunds(uint256 campaignId, uint256 withdrawAmount);
    event DepositFunds(uint256 campaignId, address user, uint256 depositAmount);
    event PendingDeposit(uint256 campaignId, address user, uint256 depositAmount);
    event RecurringDespositCreated(
        uint256 campaignId,
        address user,
        uint256 totalDepositAmount,
        uint256 recurringDepositAmount,
        uint256 depositFrequency
    );
    event CampaignCreated(
        uint256 campaignId,
        address owner,
        string name
    );

    //║══════════════════════════════════════════╗
    //║              Errors                      ║
    //║══════════════════════════════════════════╝
    error UnauthorizedSender();
    error UnauthorizedToken();

    //║══════════════════════════════════════════╗
    //║             Structs                      ║
    //║══════════════════════════════════════════╝
    struct PapaCampaign {
        address owner;
        string name;
        address tokenAddress;
        uint256 tokenAmount;
        uint256 endDate;
        bool hasEnded;
    }

    struct PapaRecurringDeposit {
        address user;
        uint256 campaignId;
        uint256 totalDepositAmount;
        uint256 donationAmountLeft;
        uint256 recurringDepositAmount;
        uint256 depositFrequency;
        uint256 lastDepositTime;
        uint256 nextDepositTime;
        bool hasEnded;
    }

    //║══════════════════════════════════════════╗
    //║             Storage                      ║
    //║══════════════════════════════════════════╝
    uint256 public campaignCount;
    uint256 public recurringDepositCount;
    address public usdcTokenAddress; //0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 usdc on Base
    address public actionCampaignAdmin;
    address public upkeep;
    bool public initialized;
    mapping(uint256 => PapaCampaign) public campaigns;
    mapping(address => mapping(uint256 => uint256)) public usersDonations;
    mapping(address => mapping(uint256 => bool)) public userHasDonated;
    mapping(uint256 => PapaRecurringDeposit) public usersRecurringDeposits;

    // Modifiers
    modifier onlyActionCampaign() {
        require(msg.sender == actionCampaignAdmin, "Token is not accepted");
        _;
    }
    modifier onlyUpkeep() {
        require(msg.sender == upkeep, "Only upkeep can call this function");
        _;
    }

    // Constructor
    constructor(address admin, address _usdcTokenAddress) ERC1155("") Ownable(msg.sender){
        usdcTokenAddress = _usdcTokenAddress;
        actionCampaignAdmin = admin;
    }

    function setUpkeep(address _upkeep) public onlyOwner {
        require(!initialized, "Upkeep already initialized");
        upkeep = _upkeep;
        initialized = true;
    }

    //║══════════════════════════════════════════╗
    //║    Admin Functions                       ║
    //║══════════════════════════════════════════╝

    //Set the actionCampaign admin address
    function setActionCampaignAdmin(address _newAdmin) onlyActionCampaign public {
        actionCampaignAdmin = _newAdmin;
    }

    //║══════════════════════════════════════════╗
    //║    Get Functions                         ║
    //║══════════════════════════════════════════╝

    // Get campaign by id
    function getCampaign(uint256 _campaignId) public view returns (PapaCampaign memory) {
        return campaigns[_campaignId];
    }

    // Get user campaigns
    function getUserCampaigns(address _user) public view returns (PapaCampaign[] memory) {
        PapaCampaign[] memory userCampaigns = new PapaCampaign[](campaignCount);
        uint256 userCampaignsCount = 0;
        for (uint256 i = 1; i <= campaignCount; i++) {
            if (campaigns[i].owner == _user) {
                userCampaigns[userCampaignsCount] = campaigns[i];
                userCampaignsCount++;
            }
        }
        return userCampaigns;
    }

    //║══════════════════════════════════════════╗
    //║    User Functions                        ║
    //║══════════════════════════════════════════╝

    // Create a new campaign
    function createCampaign(
        string memory _name,
        uint256 endDate
    ) public returns (uint256){
        // increment campaign count
        unchecked {
            campaignCount++;
        }
        // create new campaign
        campaigns[campaignCount] = PapaCampaign(
            msg.sender,
            _name,
            usdcTokenAddress,
            0,
            endDate,
            false
        );
        emit CampaignCreated(campaignCount, msg.sender, _name);
        return(campaignCount);
    }

    // End a campaign
    function endCampaign(uint256 _campaignId) public {
        require( campaigns[_campaignId].hasEnded == false, "Campaign has already ended");
        require(campaigns[_campaignId].owner == msg.sender, "You are not the owner of this campaign");
        campaigns[_campaignId].hasEnded = true;
        emit CampaignHasEnded(_campaignId);
    }
    
    // Campaign owner withdraw funds from a campaign
    function campaignWithdrawFunds(uint256 _campaignId, uint256 withdrawAmount) public {
        require(campaigns[_campaignId].owner == msg.sender, "You are not the owner of this campaign");
        require(campaigns[_campaignId].tokenAmount >= withdrawAmount, "Insufficient funds");
        IERC20(usdcTokenAddress).transfer(msg.sender, withdrawAmount);
        campaigns[_campaignId].tokenAmount -= withdrawAmount;
        emit WithdrawFunds(_campaignId, withdrawAmount);
    }

    // User deposit funds to a campaign. Directly deposit USDC
    function depositFunds(uint256 campaignId, uint256 depositAmount) public {
        _depositFunds(campaignId, depositAmount, msg.sender, false);
    }

    // User deposit funds to a campaign. Recurring deposit
    function depositFundsRecurring(address donor, uint256 campaignId, uint256 recurringAmount, uint256 donationTimes, uint256 donationInterval) public {
        // calculate total donation amount
        uint256 totalDonationAmount = recurringAmount * donationTimes;
        // transfer USDC from donor to contract
        IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), totalDonationAmount);
        // deposit first amount
        _depositFunds(campaignId, recurringAmount, donor, true);
        uint256 donationAmountLeft = totalDonationAmount - recurringAmount;
        // increment campaign count
        unchecked {
            recurringDepositCount++;
        }
        // create and store new recurring deposit
        usersRecurringDeposits[recurringDepositCount] = PapaRecurringDeposit(
            donor,
            campaignId,
            totalDonationAmount, 
            donationAmountLeft,
            recurringAmount,
            donationInterval,
            block.timestamp,
            block.timestamp + donationInterval,
            false
        );
        emit RecurringDespositCreated(campaignId, donor, totalDonationAmount, recurringAmount, donationInterval);
    }

    // Relayer trigger the recurring deposit transactions on behalf of the user
    function triggerRecurringDeposit(uint256 recurringDepositId) public {
        PapaRecurringDeposit storage recurringDeposit = usersRecurringDeposits[recurringDepositId];
        require(recurringDeposit.hasEnded == false, "Recurring deposit has ended");
        require(recurringDeposit.donationAmountLeft > 0, "No donation amount left");
        require(recurringDeposit.nextDepositTime <= block.timestamp, "It's not time to deposit yet");
        _depositFunds(recurringDeposit.campaignId, recurringDeposit.recurringDepositAmount, recurringDeposit.user, true);
        recurringDeposit.donationAmountLeft -= recurringDeposit.recurringDepositAmount;
        recurringDeposit.lastDepositTime = block.timestamp;
        recurringDeposit.nextDepositTime = block.timestamp + recurringDeposit.depositFrequency;
        if (recurringDeposit.donationAmountLeft == 0) {
            recurringDeposit.hasEnded = true;
        }
    }

    // Withdraw funds from a recurring deposit
    function withdrawRecurringDeposit(uint256 recurringDepositId) public {
        PapaRecurringDeposit storage recurringDeposit = usersRecurringDeposits[recurringDepositId];
        require(recurringDeposit.user == msg.sender, "You are not the owner of this recurring deposit");
        require(recurringDeposit.donationAmountLeft > 0, "No donation amount left");
        IERC20(usdcTokenAddress).transfer(msg.sender, recurringDeposit.donationAmountLeft);
        recurringDeposit.donationAmountLeft = 0;
        recurringDeposit.hasEnded = true;
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        for (uint256 i = 1; i <= recurringDepositCount; i++) {
            PapaRecurringDeposit storage recurringDeposit = usersRecurringDeposits[i];
            if (recurringDeposit.hasEnded == false && recurringDeposit.nextDepositTime <= block.timestamp) {
                return (true, abi.encode(i));
            }
        }
    }

    function performUpkeep(bytes calldata performData) external override onlyUpkeep{
        // decode recurring deposit id
        (uint256 recurringDepositId) = abi.decode(performData, (uint256));
        triggerRecurringDeposit(recurringDepositId);
    }

    function _depositFunds(uint256 _campaignId, uint256 depositAmount, address donor, bool isCrossChainDeposit) internal {
        require(!campaigns[_campaignId].hasEnded, "Campaign has ended");
        require(block.timestamp <= campaigns[_campaignId].endDate, "Campaign end date reached");
        if(!isCrossChainDeposit) {
            IERC20(usdcTokenAddress).transferFrom(donor, address(this), depositAmount);
        }
        // mint admin NFT
        if(campaigns[_campaignId].tokenAmount == 0) {
            _mint(actionCampaignAdmin, _campaignId, 1, "");
        }
        // mint NFT when making the first deposit
        if (userHasDonated[donor][_campaignId] == false && usersDonations[donor][_campaignId] == 0) {
            _mint(donor, _campaignId, 1, "");
            userHasDonated[donor][_campaignId] = true;
        }
        campaigns[_campaignId].tokenAmount += depositAmount;
        usersDonations[donor][_campaignId] += depositAmount;
        emit DepositFunds (_campaignId, donor, depositAmount);
    }
    
    // The following functions are overrides required by Solidity.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }
}