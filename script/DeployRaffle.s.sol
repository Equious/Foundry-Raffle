// SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Raffle} from "../src/Raffle.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

pragma solidity ^0.8.18;

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 _ticketPrice,
            uint256 interval,
            address vrfcoordinator,
            bytes32 gasLane,
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        // create subscription
        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(
                vrfcoordinator,
                deployerKey
            );
        }
        // fund subscription
        FundSubscription fundSubscription = new FundSubscription();
        fundSubscription.fundSubscription(
            vrfcoordinator,
            subscriptionId,
            link,
            deployerKey
        );

        // deploy
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            _ticketPrice,
            interval,
            vrfcoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit
        );
        vm.stopBroadcast();

        // add consumer
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(raffle),
            vrfcoordinator,
            subscriptionId,
            deployerKey
        );

        return (raffle, helperConfig);
    }
}
