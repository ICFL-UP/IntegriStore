// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract IntelliAccessControl is AccessControlEnumerable {
    /* ------------------------------ General notes ----------------------------- */
    //Allows for more fined grained control with its roles and access levels
    //assume if its in role list, then its in the mapping and vice versa

    /* -------------------------------------------------------------------------- */
    /*                           Variables and mappings                           */
    /* -------------------------------------------------------------------------- */

    struct groupleader {
        address leader;
        bytes32 role;
    }

    // bytes32[] rolegranters;//look at adding this
    mapping(bytes32 => bool) internal _roleTrack;
    mapping(bytes32 => bytes32[]) internal _subroles; // adminRole=> subroles
    mapping(bytes32 => groupleader) internal _groupLeaderMap; //groupid => groupleader
    mapping(address => bytes32[]) internal _leaderGroups; //groupleader => groups[]
    mapping(bytes32 => bytes32) internal _evidenceToGroupMap; //evidenceid => groupid
    mapping(bytes32 => bytes32) internal _groupToEvidenceMap; //groupid => evidenceid
    mapping(bytes32 => mapping(bytes32 => bool)) internal _roleGroup; // role=>group=>bool;
    mapping(address => bytes32[]) internal _userRoles; //user => roles[]
    mapping(address => bool) internal _servers;//servers


    /* -------------------------------------------------------------------------- */
    /*                                    Emits                                   */
    /* -------------------------------------------------------------------------- */
    event RoleAdded(bytes32 indexed role, bytes32 indexed adminrole);
    event RoleRemoved(bytes32 indexed role);
    event EvidenceGroupAdded(
        bytes32 indexed evidenceID,
        address indexed useraddress
    );
    event RoleGroupRemoved(bytes32 indexed group, bytes32 indexed role);
    event RoleGroupAdded(bytes32 indexed group, bytes32 indexed role);
    event EvidenceAdded(bytes32 indexed group, bytes32 indexed evidence,address indexed adder);
    event GroupLeaderChanged(
        bytes32 indexed group,
        address indexed oldaddress,
        address indexed newleader
    );
    event EvidenceRequest(
        bytes32 indexed evidenceID,
        bytes32 indexed returnhash,
        address indexed sender,
        bytes32 role
    );
    event EvidenceAccessed(
        bytes32 indexed hash,
        bytes32 indexed evidence,
        address accessor
    );
    event EvidenceSaved(
        bytes32 evid
    );
    event ServerAdded(
        address indexed server
    );
    event ServerRemoved(
        address indexed server
    );


    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */

    constructor(bytes32 role) {
        //set up superadmin
        _addRootRole(role, msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Modifiers                                 */
    /* -------------------------------------------------------------------------- */

    modifier onlyGroupLeaderOrAdmin(address add, bytes32 groupid) {
        _checkGroupLeaderOrAdmin(add, groupid);
        _;
    }

    modifier onlyAddressAdminOf(bytes32 role, address add) {
        _checkAdminOf(role, add);
        _;
    }

    function _checkGroupLeaderOrAdmin(address add, bytes32 groupid)
        internal
        view
    {
        if (!_isGroupLeaderOrAdmin(add, groupid)) {
            revert(
                "IntelliAccessControl: This account given is not the group leader"
            );
        }
    }

    function _checkAdminOf(bytes32 role, address add) internal view {
        if (!_adminOf(role, add)) {
            revert(
                string(
                    abi.encodePacked(
                        "IntelliAccessControl: Account  ",
                        Strings.toHexString(add),
                        " is not the admin/further-admin of  ",
                        Strings.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }

    function _isGroupLeaderOrAdmin(address add, bytes32 groupid)
        internal
        view
        returns (bool)
    {
        return
            _groupLeaderMap[groupid].leader == add ||
            _adminOf(_groupLeaderMap[groupid].leader, add);
    }

    function _evidenceExists(bytes32 evid) internal view returns (bool) {
        return _evidenceToGroupMap[evid] != 0x0;
    }

    /**
     * @dev internal function that checks if a role
     * @param role role we are checking
     */
    function _roleExists(bytes32 role) internal view returns (bool) {
        return _roleTrack[role];
    }

    function _groupExists(bytes32 groupid) internal view returns (bool) {
        return _groupLeaderMap[groupid].leader != address(0x0);
    }

    //if superrole is the admin of role
    function _adminOf(bytes32 role, bytes32 superrole)
        internal
        view
        returns (bool)
    {
        bytes32 curr = role;
        while (curr != 0x0) {
            if (curr == superrole) return true;
            curr = getRoleAdmin(curr);
        }
        return false;
    }

    function _adminOf(bytes32 role, address add) internal view returns (bool) {
        bytes32 curr = role;
        while (curr != 0x0) {
            if (hasRole(curr, add)) return true;
            curr = getRoleAdmin(curr);
        }
        return false;
    }

    function _adminOf(address subadd, address add)
        internal
        view
        returns (bool)
    {
        //yes this is stupid, shhhhh
        for (uint256 i = 0; i < _userRoles[subadd].length; i++) {
            if (_adminOf(_userRoles[subadd][i], add)) {
                return true;
            }
        }

        return false;
    }

    /* -------------------------------------------------------------------------- */
    /*                          Internal helper functions                         */
    /* -------------------------------------------------------------------------- */

    function _addRole(bytes32 role, bytes32 admin) internal {
        _setRoleAdmin(role, admin); //call to openzeppalins contract
        _subroles[admin].push(role);
        _roleTrack[role] = true;
        emit RoleAdded(role, admin);
    }

    function _removeRole(bytes32 role) internal {
        if (!_roleExists(role)) {
            revert("IntelliAccessControl: The given role does not exist");
        }
        //set all sub roles to this roles admin
        bytes32 temp = getRoleAdmin(role);
        for (uint256 i = 0; i < _subroles[role].length; i++) {
            _setRoleAdmin(_subroles[role][i], temp);
        }

        _setRoleAdmin(role, 0x0); //reset role to 0x0
        emit RoleRemoved(role);
    }

    function _addEvidenceGroup(
        bytes32 group,
        bytes32 role,
        address leader
    ) internal {
        _groupLeaderMap[group].leader = leader;
        _groupLeaderMap[group].role = role;
        _leaderGroups[leader].push(group);
        _addRoleGroup(role, group);
        emit EvidenceGroupAdded(group, leader);
    }

    function _addRoleGroup(
        bytes32 role,
        bytes32 group //TEMP
    ) internal  {
        bytes32 curr = role;
        while (curr != 0x0) {
            if (_roleGroup[curr][group] != true) {
                _roleGroup[curr][group] = true;
                emit RoleGroupAdded(group, role);
            } else break; //means we got to the place the role was
            curr = getRoleAdmin(curr);
        }
    }

    function _removeGroupRole(bytes32 role, bytes32 group) internal {
        //will only to the first sub role
        //remove any sub groups who have access
        if (_roleGroup[role][group]) {
            //remove access
            delete _roleGroup[role][group];
            //remove from array
        }
        for (uint256 i = 0; i < _subroles[role].length; i++) {
            if (_roleGroup[_subroles[role][i]][group])
                _removeGroupRole(_subroles[role][i], group);
        }
        emit RoleGroupRemoved(group, role);
    }

    function _changeGroupLeader(
        bytes32 group,
        address newleader,
        bytes32 newrole
    ) internal {
        bool lower = _adminOf(newrole, _groupLeaderMap[group].role);
        if (!_adminOf(_groupLeaderMap[group].role, newrole) && !lower) {
            revert(
                "IntelliAccessControl: New role must be an admin/subrole of the current role leader"
            );
        }

        //change the gorup leader
        if (lower && _groupLeaderMap[group].role != newrole) {
            //add roles from the new admin to the main admn
            _addRoleGroup(newrole, group);
            bytes32 curr = getRoleAdmin(newrole);
            while (curr != 0x0) {
                if (!_roleGroup[curr][group]) {
                    _addRoleGroup(curr, group);
                    curr = getRoleAdmin(curr);
                } else break;
            }
            _groupLeaderMap[group].role = newrole;
        }
        //change the leader
        address leader = _groupLeaderMap[group].leader;
        uint256 len = _leaderGroups[leader].length;

        for (uint256 i = 0; i < len; i++) {
            if (_leaderGroups[leader][i] == group) {
                //remove this element
                _leaderGroups[leader][i] = _leaderGroups[leader][len - 1];
                _leaderGroups[leader].pop();
            }
        }

        _leaderGroups[newleader].push(group);
        _groupLeaderMap[group].leader = newleader;
        emit GroupLeaderChanged(group, leader, newleader);
    }

    function _addEvidence(
        bytes32 evidenceid,
        bytes32 group,
        bytes32 roleid
    ) internal {
        //maybe bring this to a modifier
        if (!_roleGroup[roleid][group])
            revert(
                "IntelliAccessControl: This role does not have access to this group"
            );
        _evidenceToGroupMap[evidenceid] = group;
        _groupToEvidenceMap[group] = evidenceid;
        emit EvidenceAdded(group,evidenceid,msg.sender);
    }

    function _requestEvidence(bytes32 evidenceID, bytes32 role)
        internal
        onlyRole(role)
        returns (bytes32)
    {
        //check if this person has access to a piece of evidence
        bytes32 returnhash = keccak256(
            abi.encodePacked(
                evidenceID,
                block.timestamp,
                block.number,
                msg.sig,
                msg.sender
            )
        ); //gen random sig
        emit EvidenceRequest(evidenceID,returnhash,msg.sender,role);
        return returnhash;
    }

    function _addRootRole(bytes32 role, address add) internal {
        //sender must be a root role
        //the reaon this is okay is this function should be run VERY seldom
        _addRole(role, 0x0);
        _grantRole(role, add);
        _roleTrack[role] = true;
    }

    /* -------------------------------------------------------------------------- */
    /*                        Overridden openzep functions                        */
    /* -------------------------------------------------------------------------- */

    function _grantRole(bytes32 role, address account)
        internal
        virtual
        override
    {
        if (_adminOf(role, account))
            revert(
                "IntelliAccessControl: The account cannot possess a role it is the admin of"
            );
        if (hasRole(role, account))
            revert("IntelliAccessControl: This account already has this role");
        super._grantRole(role, account);
        _userRoles[account].push(role);
    }

    function grantRole(bytes32 role, address account)
        public
        override(AccessControl, IAccessControl)
        onlyAddressAdminOf(role, msg.sender)
    {
        //a role cannot be an admin of themsevles
        if (_adminOf(role, account) || hasRole(role, account)) {
            revert(
                "IntelliAccessControl: A role cannot to be granted to someone who has that role or is an admin of."
            );
        }
        _grantRole(role, account);
    }

    function _revokeRole(bytes32 role, address account) internal override {
        super._revokeRole(role, account);
        for (uint256 i = 0; i < _userRoles[account].length; i++) {
            if (_userRoles[account][i] == role) {
                _userRoles[account][i] = _userRoles[account][
                    _userRoles[account].length - 1
                ];
                _userRoles[account].pop();
                break;
            }
        }
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal override {
        //prevent circular dependancy
        if (_adminOf(adminRole, role)) {
            revert(
                string(
                    abi.encodePacked(
                        "IntelliAccessControl: account ",
                        Strings.toHexString(uint256(adminRole), 32),
                        " is the admin/further-admin of ",
                        Strings.toHexString(uint256(role), 32),
                        " Which will cause a circular dependency"
                    )
                )
            );
        }
        //call super contract
        super._setRoleAdmin(role, adminRole);
        //remove this role from old admins subrole
        bytes32 previousAdminRole = getRoleAdmin(role);
        for (uint256 i = 0; i < _subroles[previousAdminRole].length; i++) {
            if (_subroles[previousAdminRole][i] == role) {
                _subroles[previousAdminRole][i] = _subroles[previousAdminRole][
                    _subroles[previousAdminRole].length - 1
                ];
                _subroles[previousAdminRole].pop();
            }
        }
        //add to subroles of new admin
        _subroles[adminRole].push(role);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Public facing function                           */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Callable function to add a role
     * @param role role to add
     * @param admin the admin for this role
     */
    function addRole(bytes32 role, bytes32 admin)
        public
    // roleOrAdmin(admin, msg.sender) //ensure they either are the admin of this role
    {
        if (!_adminOf(admin, msg.sender) && !hasRole(admin, msg.sender)) {
            revert(
                "IntelliAccessControl: User does not possess the role nor is an admin of it"
            );
        }
        if (_roleExists(role)) {
            revert("IntelliAccessControl: The given already exists");
        }
        //admin cant be 0x0, but since no one is has the 0x0 role, no one
        //can grant that role
        _addRole(role, admin);
        _roleTrack[role] = true;
    }

    function addEvidenceGroup(
        bytes32 group,
        bytes32 role,
        address leader
    ) public {
        // if (!_groupExists(group)) {
        //     revert("IntelliAccessControl: The given group ID does not exist");
        // }
        if (!hasRole(role, msg.sender) && !_adminOf(role, msg.sender))
            revert(
                "IntelliAccessControl: User does not have the role, nor are they the admin of it"
            );
        if (!hasRole(role, leader) && !_adminOf(role, leader))
            revert(
                "IntelliAccessControl: Chosen leader does not have the role, nor are they the admin of it"
            );

        _addEvidenceGroup(group, role, leader);
    }

    function addRoleGroup(bytes32 role, bytes32 group)
        public
        onlyAddressAdminOf(role, msg.sender)
        onlyGroupLeaderOrAdmin(msg.sender, group)
    {
        if (!_groupExists(group)) {
            revert("IntelliAccessControl: The given group ID does not exist");
        }
        if (_roleGroup[role][group] == true)
            revert("IntelliAccessControl: Role already has access to group");
        _addRoleGroup(role, group);
    }

    function removeGroupRole(bytes32 role, bytes32 group)
        public
        onlyGroupLeaderOrAdmin(msg.sender, group)
    {
        if (!_groupExists(group)) {
            revert("IntelliAccessControl: The given group ID does not exist");
        }
        if (_groupLeaderMap[group].role == role) {
            revert(
                "IntelliAccessControl: You cannot remove a role from a group from which the leader role is"
            );
        }
        _removeGroupRole(role, group);
    }

    function addEvidence(
        bytes32 evidenceid,
        bytes32 groupid,
        bytes32 roleid
    ) public onlyRole(roleid) {
        if (_evidenceExists(evidenceid)) {
            revert(
                "IntelliAccessControl: This piece of evidence already exists"
            );
        }
        _addEvidence(evidenceid, groupid, roleid);
    }

    function addRootRole(bytes32 role, address add) public {
        if (_roleExists(role)) {
            revert("IntelliAccessControl: The given already exists");
        }
        //check sender has root role,
        for (uint256 i = 0; i < _userRoles[msg.sender].length; i++) {
            if (getRoleAdmin(_userRoles[msg.sender][i]) == 0x0) {
                //they are a root role, they can add another
                _addRootRole(role, add);
                return;
            }
        }
    }

    function removeRole(bytes32 role)
        public
        onlyAddressAdminOf(role, msg.sender)
    {
        if (getRoleMemberCount(role) != 0)
            revert(
                "IntelliAccessControl: Cannot remove a role that still has members"
            );
        _removeRole(role);
        // _roleTrack[role]=false; We dont actully want to have this happen, since this role is now "dead"
        // its address is 0x0, but no members or admins
    }

    function revokeRole(bytes32 role, address account)
        public
        override(IAccessControl, AccessControl)
        onlyAddressAdminOf(role, msg.sender)
    {
        if (_leaderGroups[account].length != 0) {
            for (uint256 i = 0; i < _leaderGroups[account].length; i++) {
                if (
                    _groupLeaderMap[_leaderGroups[account][i]].leader == account
                ) {
                    revert(
                        "IntelliAccessControl: Cannot revoke a role from one who is a group leader of a group in this role"
                    );
                }
            }
        }
        _revokeRole(role, account);
    }

    function changeGroupLeader(
        bytes32 group,
        address newleader,
        bytes32 newrole
    ) public {
        if (!hasRole(newrole, newleader)) {
            revert("IntelliAccessControl: New leader must have the new role");
        }
        //can we revoke our own access?, need to be on the same line
        if (_groupLeaderMap[group].role == newrole) {
            revert("IntelliAccessControl: New leader is already the leader");
        }
        _changeGroupLeader(group, newleader, newrole);
    }

    function requestEvidence(bytes32 evidence, bytes32 role) public returns (bytes32){
        if (_roleGroup[role][_evidenceToGroupMap[evidence]] != true) {
            revert("IntelliAccessControl: User does not have permission to view this evidence");
        }

        return _requestEvidence(evidence, role);
    }

    function addServer(address server) public {
        for (uint256 i = 0; i < _userRoles[msg.sender].length; i++) {
            if (getRoleAdmin(_userRoles[msg.sender][i]) == 0x0) {
                _servers[server]=true;
                emit ServerAdded(server);
                return;
            }
        }
    }

    function removeServer(address server) public {
        for (uint256 i = 0; i < _userRoles[msg.sender].length; i++) {
            if (getRoleAdmin(_userRoles[msg.sender][i]) == 0x0) {
                _servers[server]=false;
                emit ServerRemoved(server);
                return;
            }
        }
    }
    function saveEvidence(bytes32 evidenceid) public {
        if(!_servers[msg.sender]) revert("IntelliAccessControl: This account does not have the permission to save the evidence");
        emit EvidenceSaved(evidenceid);
    }

    function evidenceAccessed(bytes32 evidence,bytes32 hash,address accessor) public {
        if(!_servers[msg.sender]) revert("IntelliAccessControl: Account is not a registered server");
        emit EvidenceAccessed(hash, evidence, accessor);
    }

}
