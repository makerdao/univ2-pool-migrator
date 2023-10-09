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

pragma solidity >=0.8.0;

import { DssInstance } from "dss-test/MCD.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
}

interface PoolLike {
    function mint(address) external;
    function burn(address) external;
}

interface DaiNstLike {
    function daiToNst(address, uint256) external;
}

interface MkrNgtLike {
    function mkrToNgt(address, uint256) external;
}

library UniV2PoolMigratorInit {
    function init(
        DssInstance memory dss,
        address pairDaiMkr,
        address pairNstNgt
    ) internal {
        // Using pProxy instead of address(this) as otherwise won't work in tests, in real execution should be same address
        address pProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        require(GemLike(pairNstNgt).totalSupply() == 0, "UniV2PoolMigratorInit/sanity-check-1-failed");

        GemLike dai = GemLike(dss.chainlog.getAddress("MCD_DAI"));
        GemLike mkr = GemLike(dss.chainlog.getAddress("MCD_GOV"));

        uint256 daiAmtPrev = dai.balanceOf(pProxy);
        uint256 mkrAmtPrev = mkr.balanceOf(pProxy);

        GemLike(pairDaiMkr).transfer(pairDaiMkr, GemLike(pairDaiMkr).balanceOf(pProxy));
        PoolLike(pairDaiMkr).burn(pProxy);

        DaiNstLike daiNst = DaiNstLike(dss.chainlog.getAddress("DAI_NST"));
        MkrNgtLike mkrNgt = MkrNgtLike(dss.chainlog.getAddress("MKR_NGT"));

        uint256 daiAmt = dai.balanceOf(pProxy) - daiAmtPrev;
        uint256 mkrAmt = mkr.balanceOf(pProxy) - mkrAmtPrev;
        dai.approve(address(daiNst), daiAmt);
        mkr.approve(address(mkrNgt), mkrAmt);
        daiNst.daiToNst(pairNstNgt, daiAmt);
        mkrNgt.mkrToNgt(pairNstNgt, mkrAmt);
        PoolLike(pairNstNgt).mint(pProxy);

        require(GemLike(pairNstNgt).balanceOf(pProxy) > 0, "UniV2PoolMigratorInit/sanity-check-2-failed");
    }
}
