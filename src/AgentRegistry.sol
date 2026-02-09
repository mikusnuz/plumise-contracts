// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAgentRegistry.sol";

/**
 * @title AgentRegistry
 * @notice Registry for AI agents on the Plumise network
 * @dev Tracks agent registration, heartbeats, and status
 */
contract AgentRegistry is IAgentRegistry, Ownable {
    uint256 public constant HEARTBEAT_TIMEOUT = 300; // 5 minutes

    mapping(address => Agent) private agents;
    address[] private agentList;

    modifier onlyRegistered() {
        require(agents[msg.sender].wallet != address(0), "AgentRegistry: not registered");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new agent
     * @param nodeId Unique identifier for the agent node
     * @param metadata JSON metadata about the agent
     */
    function registerAgent(bytes32 nodeId, string memory metadata) external override {
        require(agents[msg.sender].wallet == address(0), "AgentRegistry: already registered");
        require(nodeId != bytes32(0), "AgentRegistry: invalid nodeId");

        agents[msg.sender] = Agent({
            wallet: msg.sender,
            nodeId: nodeId,
            metadata: metadata,
            registeredAt: block.timestamp,
            lastHeartbeat: block.timestamp,
            status: AgentStatus.ACTIVE,
            stake: 0
        });

        agentList.push(msg.sender);

        emit AgentRegistered(msg.sender, nodeId, metadata);
    }

    /**
     * @notice Update agent heartbeat to prove liveness
     */
    function heartbeat() external override onlyRegistered {
        agents[msg.sender].lastHeartbeat = block.timestamp;

        // Automatically reactivate if agent was inactive
        if (agents[msg.sender].status == AgentStatus.INACTIVE) {
            agents[msg.sender].status = AgentStatus.ACTIVE;
        }

        emit Heartbeat(msg.sender, block.timestamp);
    }

    /**
     * @notice Update agent metadata
     * @param metadata New JSON metadata
     */
    function updateMetadata(string memory metadata) external override onlyRegistered {
        agents[msg.sender].metadata = metadata;
        emit MetadataUpdated(msg.sender, metadata);
    }

    /**
     * @notice Deregister the calling agent
     */
    function deregisterAgent() external override onlyRegistered {
        bytes32 nodeId = agents[msg.sender].nodeId;

        // Remove from agent list
        for (uint256 i = 0; i < agentList.length; i++) {
            if (agentList[i] == msg.sender) {
                agentList[i] = agentList[agentList.length - 1];
                agentList.pop();
                break;
            }
        }

        delete agents[msg.sender];

        emit AgentDeregistered(msg.sender, nodeId);
    }

    /**
     * @notice Get agent information
     * @param agent Address of the agent
     * @return Agent struct
     */
    function getAgent(address agent) external view override returns (Agent memory) {
        return agents[agent];
    }

    /**
     * @notice Get all active agents (heartbeat within timeout)
     * @return Array of active agent addresses
     */
    function getActiveAgents() external view override returns (address[] memory) {
        uint256 activeCount = 0;

        // Count active agents
        for (uint256 i = 0; i < agentList.length; i++) {
            if (isActive(agentList[i])) {
                activeCount++;
            }
        }

        // Build active agents array
        address[] memory activeAgents = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < agentList.length; i++) {
            if (isActive(agentList[i])) {
                activeAgents[index] = agentList[i];
                index++;
            }
        }

        return activeAgents;
    }

    /**
     * @notice Get count of active agents
     * @return Number of active agents
     */
    function getActiveAgentCount() external view override returns (uint256) {
        uint256 count = 0;

        for (uint256 i = 0; i < agentList.length; i++) {
            if (isActive(agentList[i])) {
                count++;
            }
        }

        return count;
    }

    /**
     * @notice Slash an agent (governance function)
     * @param agent Address of the agent to slash
     */
    function slashAgent(address agent) external override onlyOwner {
        require(agents[agent].wallet != address(0), "AgentRegistry: agent not found");

        uint256 slashedAmount = agents[agent].stake;
        agents[agent].stake = 0;
        agents[agent].status = AgentStatus.SLASHED;

        emit AgentSlashed(agent, slashedAmount);
    }

    /**
     * @notice Check if agent is active (heartbeat within timeout)
     * @param agent Address of the agent
     * @return true if agent is active
     */
    function isActive(address agent) public view override returns (bool) {
        Agent memory agentData = agents[agent];

        if (agentData.wallet == address(0)) {
            return false;
        }

        if (agentData.status == AgentStatus.SLASHED) {
            return false;
        }

        return (block.timestamp - agentData.lastHeartbeat) <= HEARTBEAT_TIMEOUT;
    }

    /**
     * @notice Get total number of registered agents
     * @return Total agent count
     */
    function getTotalAgentCount() external view returns (uint256) {
        return agentList.length;
    }

    /**
     * @notice Get all registered agent addresses
     * @return Array of all agent addresses
     */
    function getAllAgents() external view returns (address[] memory) {
        return agentList;
    }

    /**
     * @notice Check if an address is registered as an agent
     * @param agent Address to check
     * @return true if the address is registered
     */
    function isRegistered(address agent) external view override returns (bool) {
        return agents[agent].wallet != address(0);
    }
}
