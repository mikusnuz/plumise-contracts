// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    bytes32 public nodeId1 = keccak256("node1");
    bytes32 public nodeId2 = keccak256("node2");
    bytes32 public nodeId3 = keccak256("node3");

    string public metadata1 = '{"name":"Alice Agent","version":"1.0"}';
    string public metadata2 = '{"name":"Bob Agent","version":"2.0"}';

    event AgentRegistered(address indexed agent, bytes32 indexed nodeId, string metadata);
    event AgentDeregistered(address indexed agent, bytes32 indexed nodeId);
    event Heartbeat(address indexed agent, uint256 timestamp);
    event AgentSlashed(address indexed agent, uint256 amount);
    event MetadataUpdated(address indexed agent, string metadata);

    function setUp() public {
        registry = new AgentRegistry();
    }

    function testRegisterAgent() public {
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(alice, nodeId1, metadata1);

        registry.registerAgent(nodeId1, metadata1);

        IAgentRegistry.Agent memory agent = registry.getAgent(alice);

        assertEq(agent.wallet, alice);
        assertEq(agent.nodeId, nodeId1);
        assertEq(agent.metadata, metadata1);
        assertEq(agent.registeredAt, block.timestamp);
        assertEq(agent.lastHeartbeat, block.timestamp);
        assertEq(uint256(agent.status), uint256(IAgentRegistry.AgentStatus.ACTIVE));
        assertEq(agent.stake, 0);

        vm.stopPrank();
    }

    function testCannotRegisterTwice() public {
        vm.startPrank(alice);

        registry.registerAgent(nodeId1, metadata1);

        vm.expectRevert("AgentRegistry: already registered");
        registry.registerAgent(nodeId1, metadata1);

        vm.stopPrank();
    }

    function testCannotRegisterWithZeroNodeId() public {
        vm.startPrank(alice);

        vm.expectRevert("AgentRegistry: invalid nodeId");
        registry.registerAgent(bytes32(0), metadata1);

        vm.stopPrank();
    }

    function testHeartbeat() public {
        vm.startPrank(alice);

        registry.registerAgent(nodeId1, metadata1);

        // Fast forward time
        vm.warp(block.timestamp + 100);

        vm.expectEmit(true, false, false, true);
        emit Heartbeat(alice, block.timestamp);

        registry.heartbeat();

        IAgentRegistry.Agent memory agent = registry.getAgent(alice);
        assertEq(agent.lastHeartbeat, block.timestamp);

        vm.stopPrank();
    }

    function testHeartbeatReactivatesInactiveAgent() public {
        vm.startPrank(alice);

        registry.registerAgent(nodeId1, metadata1);

        // Fast forward past timeout to make agent inactive
        vm.warp(block.timestamp + 400);

        // Agent should be inactive now
        assertFalse(registry.isActive(alice));

        // Heartbeat should reactivate
        registry.heartbeat();

        assertTrue(registry.isActive(alice));

        vm.stopPrank();
    }

    function testCannotHeartbeatIfNotRegistered() public {
        vm.startPrank(alice);

        vm.expectRevert("AgentRegistry: not registered");
        registry.heartbeat();

        vm.stopPrank();
    }

    function testUpdateMetadata() public {
        vm.startPrank(alice);

        registry.registerAgent(nodeId1, metadata1);

        string memory newMetadata = '{"name":"Alice Agent","version":"2.0"}';

        vm.expectEmit(true, false, false, true);
        emit MetadataUpdated(alice, newMetadata);

        registry.updateMetadata(newMetadata);

        IAgentRegistry.Agent memory agent = registry.getAgent(alice);
        assertEq(agent.metadata, newMetadata);

        vm.stopPrank();
    }

    function testDeregisterAgent() public {
        vm.startPrank(alice);

        registry.registerAgent(nodeId1, metadata1);

        assertEq(registry.getTotalAgentCount(), 1);

        vm.expectEmit(true, true, false, true);
        emit AgentDeregistered(alice, nodeId1);

        registry.deregisterAgent();

        IAgentRegistry.Agent memory agent = registry.getAgent(alice);
        assertEq(agent.wallet, address(0));

        assertEq(registry.getTotalAgentCount(), 0);

        vm.stopPrank();
    }

    function testGetActiveAgents() public {
        // Register three agents
        vm.prank(alice);
        registry.registerAgent(nodeId1, metadata1);

        vm.prank(bob);
        registry.registerAgent(nodeId2, metadata2);

        vm.prank(charlie);
        registry.registerAgent(nodeId3, metadata1);

        // All should be active
        assertEq(registry.getActiveAgentCount(), 3);

        address[] memory activeAgents = registry.getActiveAgents();
        assertEq(activeAgents.length, 3);

        // Fast forward to make some agents inactive
        vm.warp(block.timestamp + 400);

        // All should be inactive now
        assertEq(registry.getActiveAgentCount(), 0);

        // Bob sends heartbeat
        vm.prank(bob);
        registry.heartbeat();

        // Only Bob should be active
        assertEq(registry.getActiveAgentCount(), 1);

        activeAgents = registry.getActiveAgents();
        assertEq(activeAgents.length, 1);
        assertEq(activeAgents[0], bob);
    }

    function testIsActive() public {
        vm.startPrank(alice);

        registry.registerAgent(nodeId1, metadata1);

        // Should be active immediately after registration
        assertTrue(registry.isActive(alice));

        // Fast forward within timeout
        vm.warp(block.timestamp + 200);
        assertTrue(registry.isActive(alice));

        // Fast forward past timeout
        vm.warp(block.timestamp + 200);
        assertFalse(registry.isActive(alice));

        vm.stopPrank();
    }

    function testIsActiveReturnsFalseForUnregistered() public {
        assertFalse(registry.isActive(alice));
    }

    function testIsActiveReturnsFalseForSlashed() public {
        vm.prank(alice);
        registry.registerAgent(nodeId1, metadata1);

        assertTrue(registry.isActive(alice));

        // Owner slashes agent
        registry.slashAgent(alice);

        assertFalse(registry.isActive(alice));
    }

    function testSlashAgent() public {
        vm.prank(alice);
        registry.registerAgent(nodeId1, metadata1);

        vm.expectEmit(true, false, false, true);
        emit AgentSlashed(alice, 0);

        registry.slashAgent(alice);

        IAgentRegistry.Agent memory agent = registry.getAgent(alice);
        assertEq(uint256(agent.status), uint256(IAgentRegistry.AgentStatus.SLASHED));
        assertEq(agent.stake, 0);
    }

    function testCannotSlashUnregisteredAgent() public {
        vm.expectRevert("AgentRegistry: agent not found");
        registry.slashAgent(alice);
    }

    function testOnlyOwnerCanSlash() public {
        vm.prank(alice);
        registry.registerAgent(nodeId1, metadata1);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        registry.slashAgent(alice);
        vm.stopPrank();
    }

    function testGetAllAgents() public {
        vm.prank(alice);
        registry.registerAgent(nodeId1, metadata1);

        vm.prank(bob);
        registry.registerAgent(nodeId2, metadata2);

        address[] memory allAgents = registry.getAllAgents();
        assertEq(allAgents.length, 2);

        // Check that both agents are in the list
        bool foundAlice = false;
        bool foundBob = false;

        for (uint256 i = 0; i < allAgents.length; i++) {
            if (allAgents[i] == alice) foundAlice = true;
            if (allAgents[i] == bob) foundBob = true;
        }

        assertTrue(foundAlice);
        assertTrue(foundBob);
    }

    function testDeregisterRemovesFromAgentList() public {
        vm.prank(alice);
        registry.registerAgent(nodeId1, metadata1);

        vm.prank(bob);
        registry.registerAgent(nodeId2, metadata2);

        assertEq(registry.getTotalAgentCount(), 2);

        vm.prank(alice);
        registry.deregisterAgent();

        assertEq(registry.getTotalAgentCount(), 1);

        address[] memory allAgents = registry.getAllAgents();
        assertEq(allAgents.length, 1);
        assertEq(allAgents[0], bob);
    }

    function testFuzzRegisterAgent(bytes32 nodeId, string memory metadata) public {
        vm.assume(nodeId != bytes32(0));

        vm.prank(alice);
        registry.registerAgent(nodeId, metadata);

        IAgentRegistry.Agent memory agent = registry.getAgent(alice);
        assertEq(agent.nodeId, nodeId);
        assertEq(agent.metadata, metadata);
    }

    function testFuzzHeartbeatTimeout(uint256 timePassed) public {
        timePassed = bound(timePassed, 0, 1000);

        vm.prank(alice);
        registry.registerAgent(nodeId1, metadata1);

        vm.warp(block.timestamp + timePassed);

        bool expectedActive = timePassed <= registry.HEARTBEAT_TIMEOUT();
        assertEq(registry.isActive(alice), expectedActive);
    }

    function testIsRegistered() public {
        // Not registered initially
        assertFalse(registry.isRegistered(alice));

        // Register agent
        vm.prank(alice);
        registry.registerAgent(nodeId1, metadata1);

        // Should be registered
        assertTrue(registry.isRegistered(alice));

        // Deregister
        vm.prank(alice);
        registry.deregisterAgent();

        // Should not be registered anymore
        assertFalse(registry.isRegistered(alice));
    }
}
