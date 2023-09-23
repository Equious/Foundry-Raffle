//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract RaffleTest is Test {
    // events
    event RaffleEntered(address indexed entrant);

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 _ticketPrice;
    uint256 interval;
    address vrfcoordinator;
    bytes32 gasLane;
    uint64 subcriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        (raffle, helperConfig) = deployer.run();
        (
            _ticketPrice,
            interval,
            vrfcoordinator,
            gasLane,
            subcriptionId,
            callbackGasLimit
        ) = helperConfig.activeNetworkConfig();
    }

    function testRaffleIntializedInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.LotteryState.OPEN);
    }

    // Enter Raffle //

    function testRaffleRevertsWhenYouDontSendEnoughEth() public {
        // Arrange
        vm.prank(PLAYER);
        // Assert // Act
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersOnEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        assert(raffle.getNumberOfTickets() == 1);
    }

    function testRaffleReturnsPlayerWhenEntered() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        assert(raffle.getPlayer(0) == PLAYER);
    }

    function testRaffleEmitsEventsOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
    }

    function testCantEnterWhenRaffleNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleClosed.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: _ticketPrice}();
    }
}
