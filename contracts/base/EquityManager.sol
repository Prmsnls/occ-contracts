// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import "../common/SelfAuthorized.sol";
import "../common/Equity.sol";

/// @title StakeManager - Manages a set of owners and an equity structure to perform actions.
/// @author Puter Himself - <puter@prmsnls.xyz>

contract EquityManager is SelfAuthorized {
    //max stake = 10_000, (100.00 Hundred with 2 decimal places)
    //stake = 0.01% is written 1; LIMIT of 2 decimal places.
    event AddedOwner(address member);
    event RemovedOwner(address member);
    event ChangedStake(address member, uint256 threshold);

    address internal constant SENTINEL_OWNERS = address(0x1);
    mapping(address => address) internal owners;
    mapping(address => uint256) internal equityStake;
    uint256 internal ownerCount;
    uint256 internal totalEquity;
    uint256 internal allottedEquity;
    EquityToken internal equityToken;

    /// @dev Setup function sets initial storage of contract.
    /// @param _members List of Safe owners.
    /// @param _stakes List Equity percentage stake of each member
    function setupEquityStructure(
        address[] memory _members,
        uint256[] memory _stakes,
        uint256 _totalEquity
    ) internal {
        //each owners stakes should be specified.
        require(_members.length == _stakes.length, "PUTER04: SLOTH");
        // equityToken = EquityToken(createToken());
        // Initializing Safe owners.
        address currentOwner = _members[0];
        owners[SENTINEL_OWNERS] = currentOwner;
        owners[currentOwner] = SENTINEL_OWNERS;
        _addMemberAndEquity(currentOwner, _stakes[0], _totalEquity);

        for (uint256 i = 1; i < _members.length; i++) {
            // Owner address cannot be null.
            address owner = _members[i];
            uint256 stake = _stakes[i];
            require(owner != address(0) && owner != SENTINEL_OWNERS && owner != address(this) && currentOwner != owner, "GS203");
            // No duplicate owners allowed.
            require(owners[owner] == address(0), "GS204");
            require(stake > 0 && stake < totalEquity, "PUTER02: GLUTTONY");
            _addMemberAndEquity(owner, stake, 0);

            // owners[currentOwner] = owner;
            // currentOwner = owner;
            // equityStake[owner] = stake;
            // allottedEquity += stake;
            // require(allottedEquity <= totalEquity, "PUTER05: GLUTTONY");
        }
    }

    function createToken() internal returns (address) {}

    /// @param stake New stake to in percentage, for input (0.1% pass in 10, 100% = 10_000)
    function diluteEquity(uint256 stake) internal view returns (uint, uint) {
        uint256 newTotalStake = (totalEquity * 100) / (100 - stake);
        uint256 newStake = newTotalStake - totalEquity;
        return (newStake, newTotalStake);
    }

    /// @dev Allows to assign unallocated equity (if any)
    ///      This can only be done via a Safe transaction.
    /// @notice Adds the owner `owner` to the Safe and updates the threshold to `_threshold`.
    /// @param owner New owner address.
    /// @param _equity New threshold.
    function sellUnallottedEquity(address owner, uint256 _equity) public authorized {
        uint saleEquity = getUnallottedEquity();
        require(saleEquity > 0, "PUTER07: ENVY-NO SALE");
        require(_equity <= saleEquity, "PUTER06: GREED");
        _addMemberAndEquity(owner, _equity, 0);
    }

    /// @dev Allows to add a new owner to the Safe and update the threshold at the same time.
    ///      This can only be done via a Safe transaction.
    /// @notice Adds the owner `owner` to the Safe and updates the threshold to `_threshold`.
    /// @param owner New owner address.
    /// @param _stake New stake to in percentage, for input (0.1% pass in 10, 100% = 10_000)
    function addOwnerWithThreshold(address owner, uint256 _stake) public authorized {
        // Owner address cannot be null, the sentinel or the Safe itself.
        require(owner != address(0) && owner != SENTINEL_OWNERS && owner != address(this), "GS203");
        // No duplicate owners allowed.
        require(owners[owner] == address(0), "GS204");
        (uint256 equity, uint newTotalEquity) = diluteEquity(_stake);
        _addMemberAndEquity(owner, equity, newTotalEquity);
    }

    /// @dev Allows to remove an owner from the Safe and update the threshold at the same time.
    ///      This can only be done via a Safe transaction.
    /// @notice Removes the owner `owner` from the Safe and updates the threshold to `_threshold`.
    /// @param prevOwner Owner that pointed to the owner to be removed in the linked list
    /// @param owner Owner address to be removed.
    /// @param _threshold New threshold.

    function removeOwner(
        address prevOwner,
        address owner,
        uint256 _threshold
    ) public authorized {
        // Only allow to remove an owner, if threshold can still be reached.
        require(ownerCount - 1 >= _threshold, "GS201");
        // Validate owner address and check that it corresponds to owner index.
        require(owner != address(0) && owner != SENTINEL_OWNERS, "GS203");
        require(owners[prevOwner] == owner, "GS205");
        owners[prevOwner] = owners[owner];
        owners[owner] = address(0);
        equityStake[owner] = 0;
        ownerCount--;
        allottedEquity--;
    }

    /// @dev Allows to swap/replace an owner from the Safe with another address.
    ///      This can only be done via a Safe transaction.
    /// @notice Replaces the owner `oldOwner` in the Safe with `newOwner`.
    /// @param prevOwner Owner that pointed to the owner to be replaced in the linked list
    /// @param oldOwner Owner address to be replaced.
    /// @param newOwner New owner address.
    function swapOwner(
        address prevOwner,
        address oldOwner,
        address newOwner
    ) public authorized {
        // Owner address cannot be null, the sentinel or the Safe itself.
        require(newOwner != address(0) && newOwner != SENTINEL_OWNERS && newOwner != address(this), "GS203");
        // No duplicate owners allowed.
        require(owners[newOwner] == address(0), "GS204");
        // Validate oldOwner address and check that it corresponds to owner index.
        require(oldOwner != address(0) && oldOwner != SENTINEL_OWNERS, "GS203");
        require(owners[prevOwner] == oldOwner, "GS205");
        owners[newOwner] = owners[oldOwner];
        owners[prevOwner] = newOwner;
        owners[oldOwner] = address(0);

        equityStake[newOwner] = equityStake[oldOwner];
        equityStake[oldOwner] = 0;
        emit RemovedOwner(oldOwner);
        emit AddedOwner(newOwner);
    }

    function getUnallottedEquity() public view returns (uint256) {
        return totalEquity - allottedEquity;
    }

    function getStake(address _owner) public view returns (uint256) {
        return (equityStake[_owner]/totalEquity) * 100;
    }

    function isOwner(address owner) public view returns (bool) {
        return owner != SENTINEL_OWNERS && owners[owner] != address(0);
    }

    /// @dev Returns array of owners.
    /// @return Array of Safe owners.

    function getOwners() public view returns (address[] memory) {
        address[] memory array = new address[](ownerCount);

        // populate return array
        uint256 index = 0;
        address currentOwner = owners[SENTINEL_OWNERS];
        while (currentOwner != SENTINEL_OWNERS) {
            array[index] = currentOwner;
            currentOwner = owners[currentOwner];
            index++;
        }
        return array;
    }

    function _addMember(address _member) private {
        // owners[SENTINEL_OWNERS] = currentOwner;
        // owners[currentOwner] = SENTINEL_OWNERS;
        address currentOwner = owners[SENTINEL_OWNERS];
        owners[_member] = currentOwner;
        owners[SENTINEL_OWNERS] = currentOwner;
        ownerCount++;
    }

    function _addMemberAndEquity(address _member, uint256 _equity, uint _newEquity) private {
        if (owners[_member] != address(0)) _addMember(_member);
        if (_newEquity != 0) totalEquity = _newEquity;
        equityStake[_member] += _equity;
        allottedEquity += _equity;
        require(allottedEquity <= totalEquity, "PUTER05: GLUTTONY");
    }
}
