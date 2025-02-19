// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";

import { UniV2PoolWithdraw } from "deploy/UniV2PoolWithdraw.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface PoolLike {
    function getReserves() external view returns (uint112, uint112, uint32);
}

interface PipLike {
    function src() external view returns (address);
}

contract WithdrawTest is DssTest {
    address constant LOG                 = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant UNIV2_USDS_SKY_PAIR = 0x2621CC0B3F3c079c1Db0E80794AA24976F0b9e3c;

    address PAUSE_PROXY;
    address USDS;
    address SKY;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        PAUSE_PROXY = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");
        USDS        = ChainlogLike(LOG).getAddress("USDS");
        SKY         = ChainlogLike(LOG).getAddress("SKY");
    }

    function testWithdraw() public {
        DssInstance memory dss = MCD.loadFromChainlog(LOG);

        (uint256 skyReservePrev, uint256 usdsReservePrev, ) = PoolLike(UNIV2_USDS_SKY_PAIR).getReserves();
        uint256 pProxyUsdsSkyPrev = GemLike(UNIV2_USDS_SKY_PAIR).balanceOf(PAUSE_PROXY);
        uint256 pProxyUsdsPrev    = GemLike(USDS).balanceOf(PAUSE_PROXY);
        uint256 pProxySkyPrev     = GemLike(SKY).balanceOf(PAUSE_PROXY);
        uint256 totalSupplyPrev   = GemLike(UNIV2_USDS_SKY_PAIR).totalSupply();

        vm.startPrank(PAUSE_PROXY);
        UniV2PoolWithdraw.withdraw(dss, 7_500_000 * 1e18);
        vm.stopPrank();

        // expected withdraw is initial owned usds - leave amount
        uint256 expectedUsdsWithdraw = usdsReservePrev * pProxyUsdsSkyPrev / totalSupplyPrev - 7_500_000 * 1e18;
        assertApproxEqAbs(GemLike(USDS).balanceOf(PAUSE_PROXY), pProxyUsdsPrev + expectedUsdsWithdraw, 1000);

        uint256 expectedSkyWithdraw  = expectedUsdsWithdraw * skyReservePrev / usdsReservePrev;
        assertApproxEqAbs(GemLike(SKY).balanceOf(PAUSE_PROXY), pProxySkyPrev + expectedSkyWithdraw, 1000);

        uint256 expectedLpBurn = expectedUsdsWithdraw * totalSupplyPrev / usdsReservePrev;
        assertApproxEqAbs(GemLike(UNIV2_USDS_SKY_PAIR).balanceOf(PAUSE_PROXY), pProxyUsdsSkyPrev - expectedLpBurn, 1000);

        uint256 expectedExactLpBurn = totalSupplyPrev - GemLike(UNIV2_USDS_SKY_PAIR).totalSupply();
        assertEq(GemLike(UNIV2_USDS_SKY_PAIR).balanceOf(PAUSE_PROXY), pProxyUsdsSkyPrev - expectedExactLpBurn);

        uint256 expectedExactUsdsWithdraw = expectedExactLpBurn * (GemLike(USDS).balanceOf(UNIV2_USDS_SKY_PAIR) + GemLike(USDS).balanceOf(PAUSE_PROXY) - pProxyUsdsPrev) / totalSupplyPrev;
        assertEq(GemLike(USDS).balanceOf(PAUSE_PROXY), pProxyUsdsPrev + expectedExactUsdsWithdraw);

        uint256 expectedExactSkyWithdraw  = expectedExactLpBurn * (GemLike(SKY).balanceOf(UNIV2_USDS_SKY_PAIR) + GemLike(SKY).balanceOf(PAUSE_PROXY) - pProxySkyPrev) / totalSupplyPrev;
        assertEq(GemLike(SKY).balanceOf(PAUSE_PROXY), pProxySkyPrev + expectedExactSkyWithdraw);

        // do another withdraw and this time leave nothing
        vm.startPrank(PAUSE_PROXY);
        UniV2PoolWithdraw.withdraw(dss, 0);
        vm.stopPrank();

        // pause proxy should now hold its initial funds + initial owned funds
        assertApproxEqAbs(GemLike(USDS).balanceOf(PAUSE_PROXY), pProxyUsdsPrev + usdsReservePrev * pProxyUsdsSkyPrev / totalSupplyPrev, 1000);
        assertApproxEqAbs(GemLike(SKY).balanceOf(PAUSE_PROXY),  pProxySkyPrev + skyReservePrev * pProxyUsdsSkyPrev / totalSupplyPrev, 1000);
        assertEq(GemLike(UNIV2_USDS_SKY_PAIR).balanceOf(PAUSE_PROXY), 0);

        expectedExactLpBurn = totalSupplyPrev - GemLike(UNIV2_USDS_SKY_PAIR).totalSupply();
        assertEq(GemLike(USDS).balanceOf(PAUSE_PROXY), pProxyUsdsPrev + expectedExactLpBurn * (GemLike(USDS).balanceOf(UNIV2_USDS_SKY_PAIR) + GemLike(USDS).balanceOf(PAUSE_PROXY) - pProxyUsdsPrev) / totalSupplyPrev);
        assertEq(GemLike(SKY).balanceOf(PAUSE_PROXY),  pProxySkyPrev + expectedExactLpBurn * (GemLike(SKY).balanceOf(UNIV2_USDS_SKY_PAIR) + GemLike(SKY).balanceOf(PAUSE_PROXY) - pProxySkyPrev) / totalSupplyPrev);
    }

    function checkPriceSanityCheck(uint256 newMedianizerPrice) public {
        DssInstance memory dss = MCD.loadFromChainlog(LOG);
        address mkrMedianizer = PipLike(ChainlogLike(LOG).getAddress("PIP_MKR")).src();

        vm.store(mkrMedianizer, bytes32(uint256(1)), bytes32(newMedianizerPrice));
        vm.startPrank(PAUSE_PROXY);
        UniV2PoolWithdraw.withdraw(dss, 7_500_000 * 1e18);
        vm.stopPrank();
    }

    function testPriceSanityCheck() public {
        (uint256 skyReserve, uint256 usdsReserve, ) = PoolLike(UNIV2_USDS_SKY_PAIR).getReserves();
        uint256 uniMkrPrice = (usdsReserve * 1e18 / skyReserve) * 24_000;

        vm.expectRevert("UniV2PoolWithdraw/sanity-check-failed");
        this.checkPriceSanityCheck(uniMkrPrice * 100 / 103);

        vm.expectRevert("UniV2PoolWithdraw/sanity-check-failed");
        this.checkPriceSanityCheck(uniMkrPrice * 100 / 97);

        // No revert
        this.checkPriceSanityCheck(uniMkrPrice);
    }
}
