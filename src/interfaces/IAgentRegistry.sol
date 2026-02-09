// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAgentRegistry {
    enum AgentStatus {
        ACTIVE,
        INACTIVE,
        SLASHED
    }

    struct Agent {
        address wallet;
        bytes32 nodeId;
        string metadata;
        uint256 registeredAt;
        uint256 lastHeartbeat;
        AgentStatus status;
        uint256 stake;
    }

    event AgentRegistered(address indexed agent, bytes32 indexed nodeId, string metadata);
    event AgentDeregistered(address indexed agent, bytes32 indexed nodeId);
    event Heartbeat(address indexed agent, uint256 timestamp);
    event AgentSlashed(address indexed agent, uint256 amount);
    event MetadataUpdated(address indexed agent, string metadata);

    function registerAgent(bytes32 nodeId, string memory metadata) external;
    function heartbeat() external;
    function updateMetadata(string memory metadata) external;
    function deregisterAgent() external;
    function getAgent(address agent) external view returns (Agent memory);
    function getActiveAgents() external view returns (address[] memory);
    function getActiveAgentCount() external view returns (uint256);
    function slashAgent(address agent) external;
    function isActive(address agent) external view returns (bool);
    function isRegistered(address agent) external view returns (bool);
}
