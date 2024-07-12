// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ActionsRegistry {

    //║══════════════════════════════════════════╗
    //║             Structs                      ║
    //║══════════════════════════════════════════╝
    struct Action {
        ActionStatus status;
        address actionOwner;
    }
    enum ActionStatus {
        PENDING,
        CONFIRMED,
        REMOVED
    }

    //║══════════════════════════════════════════╗
    //║              Events                      ║
    //║══════════════════════════════════════════╝
    event ActionAdded(string actionBaseUrl, address actionOwner, ActionStatus status);
    event ActionConfirmed(string actionBaseUrl);
    event ActionRemoved(string actionBaseUrl);

    //║══════════════════════════════════════════╗
    //║             Storage                      ║
    //║══════════════════════════════════════════╝
    address public owner;
    bool public restricted;

    mapping(string => Action) public actions;

    // Constructor
    constructor(address _owner) {
        owner = _owner;
        restricted = true;
    }

    //║══════════════════════════════════════════╗
    //║    Users Functions                       ║
    //║══════════════════════════════════════════╝
    function addNewAction(string memory actionBaseUrl) public {
        // check if action already exists
        require(actions[actionBaseUrl].actionOwner == address(0), "Action already exists");
        // check if restricted
        if(restricted) {
            actions[actionBaseUrl] = Action(ActionStatus.PENDING, msg.sender);
        } else {
            actions[actionBaseUrl] = Action(ActionStatus.CONFIRMED, msg.sender);
        }
        emit ActionAdded(actionBaseUrl, msg.sender, actions[actionBaseUrl].status);
    }

    function confirmAction(string memory actionBaseUrl) public {
        require(msg.sender == owner, "Only owner can confirm action");
        require(actions[actionBaseUrl].status == ActionStatus.PENDING, "Action is not pending");
        actions[actionBaseUrl].status = ActionStatus.CONFIRMED;
        emit ActionConfirmed(actionBaseUrl);
    }

    function removeAction(string memory actionBaseUrl) public {
        require(msg.sender == owner, "Only owner can confirm action");
        require(actions[actionBaseUrl].status == ActionStatus.PENDING, "Action is not pending");
        actions[actionBaseUrl].status = ActionStatus.REMOVED;
        emit ActionRemoved(actionBaseUrl);
    }

    function setRestricted(bool _restricted) public {
        require(msg.sender == owner, "Only owner can change restricted status");
        restricted = _restricted;
    }
}
