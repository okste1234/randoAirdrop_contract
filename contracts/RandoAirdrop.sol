// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RandoAirdrop is VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;

    IERC20 public token;
    address public owner;

    address[] public participantAddresses;

    address[] winners;

    uint256 public totalEntries;

    uint256 public prizePool;

    bool public isSelectionComplete;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint256 public randomResultRequestId;

    bytes32 keyHash =
        0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint16 requestConfirmations;

    uint32 numWords;

    uint32 callbackGasLimit = 100000;

    bool winnerConfigured;

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

    struct Participant {
        uint256 entries;
        string[] postContent;
        bool isRegistered;
        address addr;
    }

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }

    mapping(uint256 => RequestStatus) public requests;

    mapping(address => Participant) public participants;

    event ParticipantRegistered(address participant);
    event ActivityParticipated(address participant, uint256 entries);
    event PrizeDistributionTriggered(uint256 requestId, uint32 numWords);
    event WinnersSelected(address[] winners, uint256 amounts);
    event AirdropDistributed(address winner, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    function registerParticipant() external {
        require(!participants[msg.sender].isRegistered, "Already registered");
        participants[msg.sender].isRegistered = true;
        participants[msg.sender].addr = msg.sender;
        emit ParticipantRegistered(msg.sender);
    }

    function createPost(
        string memory _content
    ) external returns (uint256 entries_) {
        require(participants[msg.sender].isRegistered, "Not registered");

        require(totalEntries != 10, "activity ended");

        participants[msg.sender].postContent.push(_content);

        totalEntries = totalEntries + 1;

        participants[msg.sender].entries = participants[msg.sender].entries + 1;

        participantAddresses.push(msg.sender);

        entries_ = participants[msg.sender].entries;

        emit ActivityParticipated(msg.sender, entries_);
    }

    //Function to configure the number of winners and total prize
    function configureSelection(
        uint32 _numberOfWinners,
        uint256 _totalPrize
    ) external onlyOwner {
        require(!isSelectionComplete, "Selection process is already complete");
        require(
            _numberOfWinners < participantAddresses.length,
            "Number of winners exceeds total participants"
        );

        require(
            token.balanceOf(msg.sender) >= _totalPrize,
            "prize greater available token balance"
        );

        numWords = _numberOfWinners;
        prizePool = _totalPrize;

        token.transferFrom(msg.sender, address(this), prizePool);

        winnerConfigured = true;
    }

    function triggerPrizeDistribution()
        external
        onlyOwner
        returns (uint256 requestId)
    {
        require(winnerConfigured, "configure winners number first");

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

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(_requestId == randomResultRequestId, "Invalid request ID");
        require(requests[_requestId].exists, "request not found");
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

    function distributeAirdrop() external onlyOwner {
        require(isSelectionComplete, "Selection process not yet complete");

        require(winners.length > 0, "No winners selected");

        uint winnersEntries;

        // Calculate total entries of all winners
        for (uint256 i = 0; i < winners.length; i++) {
            winnersEntries += participants[winners[i]].entries;
        }

        // Distribute the prize pool proportionally based on each winner entries
        for (uint256 i = 0; i < winners.length; i++) {
            address winner = winners[i];
            uint256 winnerEntries = participants[winner].entries;
            uint256 airdropAmount = (winnerEntries * prizePool) /
                winnersEntries;

            // Transfer airdrop amount to the winner
            token.transfer(winner, airdropAmount);

            emit AirdropDistributed(winner, airdropAmount);
        }
    }
}
