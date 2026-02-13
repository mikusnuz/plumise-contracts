// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/AgentRegistry.sol";

/**
 * @title AgentRegistryHandler
 * @notice Handler contract for invariant testing that interacts with AgentRegistry
 */
contract AgentRegistryHandler is Test {
    AgentRegistry public registry;

    address[] public actors;
    mapping(address => bool) public registeredGhost;
    uint256 public registeredCountGhost;

    bytes32[] public nodeIds;

    function getActorsLength() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    constructor(AgentRegistry _registry) {
        registry = _registry;

        // Create some actors
        for (uint256 i = 0; i < 10; i++) {
            address actor = address(uint160(0x2000 + i));
            actors.push(actor);
            vm.deal(actor, 1 ether);
        }

        // Prepare unique node IDs
        for (uint256 i = 0; i < 10; i++) {
            nodeIds.push(keccak256(abi.encodePacked("node", i)));
        }
    }

    function registerAgent(uint256 actorSeed, uint256 nodeIdSeed) public {
        address actor = actors[actorSeed % actors.length];
        bytes32 nodeId = nodeIds[nodeIdSeed % nodeIds.length];

        if (!registeredGhost[actor]) {
            vm.prank(actor);
            try registry.registerAgent(nodeId, "metadata") {
                registeredGhost[actor] = true;
                registeredCountGhost++;
            } catch {}
        }
    }

    function heartbeat(uint256 actorSeed) public {
        address actor = actors[actorSeed % actors.length];

        if (registeredGhost[actor]) {
            vm.prank(actor);
            try registry.heartbeat() {} catch {}
        }
    }

    function updateMetadata(uint256 actorSeed, string memory metadata) public {
        address actor = actors[actorSeed % actors.length];

        if (registeredGhost[actor]) {
            vm.prank(actor);
            try registry.updateMetadata(metadata) {} catch {}
        }
    }

    function deregisterAgent(uint256 actorSeed) public {
        address actor = actors[actorSeed % actors.length];

        if (registeredGhost[actor]) {
            vm.prank(actor);
            try registry.deregisterAgent() {
                registeredGhost[actor] = false;
                registeredCountGhost--;
            } catch {}
        }
    }

    function advanceTime(uint256 seconds_) public {
        seconds_ = bound(seconds_, 1, 1000);
        vm.warp(block.timestamp + seconds_);
    }
}

/**
 * @title AgentRegistryInvariantTest
 * @notice Invariant tests for AgentRegistry contract
 */
contract AgentRegistryInvariantTest is Test {
    AgentRegistry public registry;
    AgentRegistryHandler public handler;

    function setUp() public {
        // Deploy registry
        registry = new AgentRegistry();

        // Deploy handler
        handler = new AgentRegistryHandler(registry);

        // Target handler for invariant tests
        targetContract(address(handler));
    }

    /**
     * @notice Invariant: Registered agent count matches total
     * @dev The number of registered agents should equal getTotalAgentCount()
     */
    function invariant_registeredCountMatch() public view {
        uint256 totalCount = registry.getTotalAgentCount();
        uint256 ghostCount = handler.registeredCountGhost();

        assertEq(totalCount, ghostCount, "Registered count mismatch");
    }

    /**
     * @notice Invariant: No duplicate agents
     * @dev All agents in agentList should be unique (no duplicates)
     */
    function invariant_noDuplicateAgents() public view {
        address[] memory allAgents = registry.getAllAgents();

        // Check for duplicates
        for (uint256 i = 0; i < allAgents.length; i++) {
            for (uint256 j = i + 1; j < allAgents.length; j++) {
                assertFalse(
                    allAgents[i] == allAgents[j],
                    "Duplicate agent found in registry"
                );
            }
        }
    }

    /**
     * @notice Invariant: Registered agents exist in list
     * @dev If an agent is registered (non-zero wallet), it should be in getAllAgents()
     */
    function invariant_registeredAgentsInList() public view {
        uint256 actorsLength = handler.getActorsLength();
        for (uint256 i = 0; i < actorsLength; i++) {
            address actor = handler.getActor(i);
            bool isRegistered = handler.registeredGhost(actor);

            if (isRegistered) {
                IAgentRegistry.Agent memory agent = registry.getAgent(actor);
                assertEq(agent.wallet, actor, "Registered agent wallet mismatch");

                // Verify actor is in the list
                address[] memory allAgents = registry.getAllAgents();
                bool foundInList = false;
                for (uint256 j = 0; j < allAgents.length; j++) {
                    if (allAgents[j] == actor) {
                        foundInList = true;
                        break;
                    }
                }
                assertTrue(foundInList, "Registered agent not in list");
            }
        }
    }

    /**
     * @notice Invariant: Active count consistency
     * @dev getActiveAgentCount() should match the number of agents returned by getActiveAgents()
     */
    function invariant_activeCountConsistency() public view {
        uint256 activeCount = registry.getActiveAgentCount();
        address[] memory activeAgents = registry.getActiveAgents();

        assertEq(activeCount, activeAgents.length, "Active count mismatch with active agents array");
    }

    /**
     * @notice Invariant: Active agents are registered
     * @dev All active agents should be registered (isRegistered = true)
     */
    function invariant_activeAgentsAreRegistered() public view {
        address[] memory activeAgents = registry.getActiveAgents();

        for (uint256 i = 0; i < activeAgents.length; i++) {
            assertTrue(
                registry.isRegistered(activeAgents[i]),
                "Active agent is not registered"
            );
        }
    }

    /**
     * @notice Invariant: isActive consistency
     * @dev If isActive(agent) returns true, the agent should be in getActiveAgents()
     */
    function invariant_isActiveConsistency() public view {
        address[] memory allAgents = registry.getAllAgents();
        address[] memory activeAgents = registry.getActiveAgents();

        for (uint256 i = 0; i < allAgents.length; i++) {
            bool active = registry.isActive(allAgents[i]);

            if (active) {
                // Verify agent is in active list
                bool foundInActive = false;
                for (uint256 j = 0; j < activeAgents.length; j++) {
                    if (activeAgents[j] == allAgents[i]) {
                        foundInActive = true;
                        break;
                    }
                }
                assertTrue(foundInActive, "Active agent not in active list");
            }
        }
    }

    /**
     * @notice Invariant: Total count never exceeds actors
     * @dev Total registered agents should never exceed the number of unique actors
     */
    function invariant_totalCountBounded() public view {
        uint256 totalCount = registry.getTotalAgentCount();
        uint256 actorsLength = handler.getActorsLength();
        assertLe(totalCount, actorsLength, "Total count exceeds possible actors");
    }

    /**
     * @notice Invariant: Deregistered agents not in list
     * @dev If an agent is not in ghost registry, it should not be in getAllAgents()
     */
    function invariant_deregisteredAgentsNotInList() public view {
        address[] memory allAgents = registry.getAllAgents();
        uint256 actorsLength = handler.getActorsLength();

        for (uint256 i = 0; i < actorsLength; i++) {
            address actor = handler.getActor(i);
            bool isRegistered = handler.registeredGhost(actor);

            if (!isRegistered) {
                // Verify actor is NOT in the list
                for (uint256 j = 0; j < allAgents.length; j++) {
                    assertFalse(
                        allAgents[j] == actor,
                        "Deregistered agent found in list"
                    );
                }
            }
        }
    }
}
