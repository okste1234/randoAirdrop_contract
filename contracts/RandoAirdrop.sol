// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Importing necessary contracts from Chainlink and OpenZeppelin libraries
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Contract for conducting a random airdrop using Chainlink VRF
contract RandoAirdrop is VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface COORDINATOR; // Instance of Chainlink's VRFCoordinatorV2Interface
    uint64 s_subscriptionId; // Subscription ID for Chainlink VRF

    IERC20 token; // Instance of the ERC20 token contract
    address owner; // Address of the owner of the contract

    address[] public participantAddresses; // Array to store addresses of participants
    address[] winners; // Array to store addresses of winners

    uint256 public totalEntries; // Total number of entries in the activity
    uint256 public prizePool; // Total prize pool for the winners

    bool isSelectionComplete; // Flag indicating whether winner selection process is complete

    // Array to store past request IDs
    uint256[] public requestIds;
    uint256 public lastRequestId; // ID of the last request made for randomness

    bytes32 keyHash =
        0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // Key hash used for Chainlink VRF

    uint16 requestConfirmations; // Number of confirmations required for a randomness request

    uint32 numWords; // Number of random words to be generated
    uint32 callbackGasLimit = 400000; // Gas limit for the callback function

    bool winnerConfigured; // Flag indicating whether winners are configured

    // Mapping to store request status based on requestId
    mapping(uint256 => RequestStatus) public requests;

    // Mapping to store participant details based on address
    mapping(address => Participant) public participants;

    // Struct to represent participant details
    struct Participant {
        uint256 entries; // Number of entries by the participant
        string[] postContent; // Content posted by the participant
        bool isRegistered; // Flag indicating participant registration status
        address addr; // Address of the participant
    }

    // Struct to represent status of a randomness request
    struct RequestStatus {
        bool fulfilled; // Whether the request has been successfully fulfilled
        bool exists; // Whether a requestId exists
        uint256[] randomWords; // Array to store the generated random words
    }

    // Constructor to initialize the contract with subscription ID and token address
    constructor(
        uint64 subscriptionId,
        address _tokenAddress
    ) VRFConsumerBaseV2(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625) {
        COORDINATOR = VRFCoordinatorV2Interface(
            0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
        );
        s_subscriptionId = subscriptionId;
        owner = msg.sender;
        token = IERC20(_tokenAddress);
    }

    // Event emitted when a participant is registered
    event ParticipantRegistered(address participant);

    // Event emitted when a participant participates in the activity
    event ActivityParticipated(address participant, uint256 entries);

    // Event emitted when prize distribution process is triggered
    event PrizeDistributionTriggered(uint256 requestId, uint32 numWords);

    // Event emitted when winners are selected
    event WinnersSelected(address[] winners, uint256 amounts);

    // Event emitted when airdrop is distributed to a winner
    event AirdropDistributed(address winner, uint256 amount);

    // Function for participants to register
    function registerParticipant() external {
        require(!participants[msg.sender].isRegistered, "Already registered");

        participants[msg.sender].isRegistered = true;

        participants[msg.sender].addr = msg.sender;

        emit ParticipantRegistered(msg.sender);
    }

    // Function for participants to create a post and earn entries
    function createPost(
        string memory _content
    ) external returns (uint256 entries_) {
        require(participants[msg.sender].isRegistered, "Not registered");
        require(totalEntries != 10, "Activities ended");

        participants[msg.sender].postContent.push(_content);
        totalEntries += 1;
        participants[msg.sender].entries += 1;
        participantAddresses.push(msg.sender);
        entries_ = participants[msg.sender].entries;

        emit ActivityParticipated(msg.sender, entries_);
    }

    // Function for the owner to configure the number of winners and total prize
    function configureSelection(
        uint32 _numberOfWinners,
        uint256 _totalPrize
    ) external {
        onlyOwner();

        require(!isSelectionComplete, "Selection process is already complete");
        require(
            _numberOfWinners < participantAddresses.length,
            "Number of winners exceeds total participants"
        );
        require(
            token.balanceOf(msg.sender) >= _totalPrize,
            "Prize greater than available token balance"
        );

        numWords = _numberOfWinners;
        prizePool = _totalPrize;

        token.transferFrom(msg.sender, address(this), _totalPrize);

        winnerConfigured = true;
    }

    // Function for the owner to trigger the prize distribution process
    function triggerPrizeDistribution() external returns (uint256 requestId) {
        onlyOwner();

        require(winnerConfigured, "Configure winners number first");

        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        RequestStatus storage requestStatus = requests[requestId];
        requestStatus.exists = true;

        requestIds.push(requestId);
        lastRequestId = requestId;

        emit PrizeDistributionTriggered(requestId, numWords);

        return requestId;
    }

    // Internal function to handle the fulfillment of random words request
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(requests[_requestId].exists, "Request not found");

        requests[_requestId].fulfilled = true;
        requests[_requestId].randomWords = _randomWords;

        _selectWinners(_requestId);
    }

    // Internal function to select winners based on the generated random number
    function _selectWinners(uint256 _requestId) internal {
        isSelectionComplete = true;

        for (uint256 i = 0; i < numWords; i++) {
            uint256 index = (requests[_requestId].randomWords[i] + i) %
                participantAddresses.length;

            winners.push(participantAddresses[index]);

            emit WinnersSelected(winners, numWords);
        }
    }

    function getWinners() external view returns (address[] memory) {
        return winners;
    }

    // Function to distribute the airdrop prizes to the winners
    function distributeAirdrop() external {
        onlyOwner();

        // Ensure that the winner selection process is complete
        require(isSelectionComplete, "Selection process not yet complete");

        // Ensure that there are winners selected
        require(winners.length > 0, "No winners selected");

        uint winnersEntries;

        // Calculate total entries of all winners
        for (uint256 i = 0; i < winners.length; i++) {
            winnersEntries += participants[winners[i]].entries;
        }

        // Distribute the prize pool proportionally based on each winner's entries
        for (uint256 i = 0; i < winners.length; i++) {
            address winner = winners[i];
            uint256 winnerEntries = participants[winner].entries;

            // Calculate the airdrop amount for the winner
            uint256 airdropAmount = (winnerEntries * prizePool) /
                winnersEntries;

            // Transfer the airdrop amount to the winner
            token.transfer(winner, airdropAmount);

            // Emit an event indicating the distribution of airdrop to the winner
            emit AirdropDistributed(winner, airdropAmount);
        }
    }

    // A helper function to set onlyowner access control
    function onlyOwner() private view {
        require(msg.sender == owner, "Only owner can call this function.");
    }
}
