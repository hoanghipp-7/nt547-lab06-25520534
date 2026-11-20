# NT547 - LAB 06 - BÁO CÁO

**MSSV:** 25520534 | **Họ tên:** Hồ Hoàng Hiệp | **Lớp:** NT547.R11.ANTT
**Session code tự sinh:** SC-EE5D6C | **Tên contract:** TipJar_0534
**Solidity / Slither:** 0.8.24 / 0.11.6 | **Ngày hoàn thành:** 20/11/2026
**URL GitHub repository:** https://github.com/hoanghipp-7/nt547-lab06-25520534

## 1. Static scan (2,0 điểm)

- Lệnh raw: `python tools/scan.py --mode raw --tag before`
- Số lượng finding raw từ `evidence/before_raw/summary.json` (tổng 12):
  - High: 3; Medium: 3; Low: 1; Informational: 5; Optimization: 0
- Chạy configured: `python tools/scan.py --mode configured --tag before`
- So sánh raw/configured: config `slither.config.json` chỉ bật `exclude_low`, `exclude_informational` và loại `solc-version`. Vì vậy bản configured chỉ ẩn Low/Informational (6 finding), còn 3 High + 3 Medium vẫn nguyên. (Điền số thực từ `evidence/before_configured/summary.json`: High 3, Medium 3, tổng 6.) Đổi config không làm biến mất High/Medium.
- 3 detector khác tên: `reentrancy-eth`, `tx-origin`, `controlled-delegatecall` (ngoài ra còn `weak-prng`, `incorrect-equality`, `unchecked-lowlevel`).

| ID finding | Detector | Impact | Confidence | Source (file:dòng) | Luồng dữ liệu: đầu vào -> thao tác -> tác hại |
|---|---|---|---|---|---|
| F01 | reentrancy-eth | High | Medium | AuditTarget.sol:46-52 (call dòng 49, ghi state dòng 51) | Người gọi `redeem()` (contract độc hại) -> `msg.sender.call{value: amount}` gửi ETH trước khi `ledger[msg.sender] = 0` -> fallback gọi lại `redeem()` khi ledger chưa về 0, rút lặp lại, hút cạn quỹ |
| F02 | tx-origin | Medium | Medium | AuditTarget.sol:35-39 (dòng 36) | Chủ sở hữu bị lừa gọi contract lừa đảo -> contract đó gọi `updateOwner(attacker)`, `tx.origin` vẫn là owner nên qua check -> attacker thành owner |
| F03 | controlled-delegatecall | High | Medium | AuditTarget.sol:54-57 (dòng 55) | Ai cũng gọi `plugin(target, data)` -> `target.delegatecall(data)` chạy code người khác trong storage của TipJar -> ghi đè `owner` hoặc `selfdestruct`, chiếm toàn bộ |

Các finding còn lại của baseline: weak-prng (High, Medium, dòng 63-65), incorrect-equality (Medium, High, dòng 59-61), unchecked-lowlevel (Medium, Medium, dòng 41-44), missing-zero-check (Low), 4x low-level-calls và naming-convention (Informational).

## 2. Triage và sửa lỗi (2,5 điểm)

4 mẫu lỗi thật + 2 đoạn cần đánh giá ngữ cảnh. Cả 6 đều được Slither báo.

| Detector + vị trí | TP / FP / Chưa kết luận | Bằng chứng kiểm soát/khả năng khai thác | Biện pháp (Fix / Accept có lý do) | Sau sửa |
|---|---|---|---|---|
| reentrancy-eth, `redeem()` dòng 46-52 | TP | Gửi ETH (dòng 49) trước khi xoá `ledger` (dòng 51); không có guard | Fix: đảo thứ tự Checks-Effects-Interactions, `ledger[msg.sender] = 0` trước `call` | Hết finding |
| tx-origin, `updateOwner` dòng 35-39 | TP | Dùng `tx.origin == owner` để xác thực, bị phishing qua contract trung gian | Fix: chuyển sang modifier `onlyOwner` (dùng `msg.sender`) | Hết finding |
| controlled-delegatecall, `plugin` dòng 54-57 | TP (ban đầu) | Không có access control, `target` do caller chọn | Fix: thêm `onlyOwner`, bỏ tham số `target`, dùng `address immutable module` cố định lúc deploy. Lần sửa đầu Slither vẫn báo, nên lần hai suppress có lý do | Suppressed (`slither-disable-next-line controlled-delegatecall`), xem mục Accept bên dưới |
| unchecked-lowlevel, `rescueEth` dòng 41-44 | TP | Bỏ qua giá trị trả về của `to.call`, chuyển ETH thất bại mà vẫn coi như thành công | Fix: `(bool ok,) = to.call{...}; require(ok, "rescue failed")` | Hết finding |
| incorrect-equality, `vaultDrained` dòng 59-61 | FP về risk (chấp nhận) | Chỉ là view đọc `address(this).balance == 0`, không gate logic chuyển tiền; kẻ tấn công ép gửi ETH (selfdestruct) chỉ làm hàm trả `false` | Accept: `slither-disable-next-line incorrect-equality` kèm lý do | Suppressed |
| weak-prng, `displayDay` dòng 63-65 | FP về risk (chấp nhận) | Dùng `block.timestamp` để hiển thị thứ trong tuần, không phải ngẫu nhiên và không liên quan tiền hay quyền | Accept: `slither-disable-next-line weak-prng` | Suppressed |

- Kịch bản khai thác TP (reentrancy): attacker triển khai contract A, gọi `contribute()` với 1 ETH -> A gọi `redeem()`, `ledger[A] = 1 ETH` qua check `amount > 0` -> TipJar gửi 1 ETH cho A bằng `call` -> fallback của A gọi lại `redeem()` khi `ledger[A]` chưa về 0 -> lặp đến khi TipJar hết ETH -> thất thoát tiền của người đóng góp khác.
- Finding severity cao nhưng risk thực tế thấp: `controlled-delegatecall` ở `plugin` sau khi sửa. Slither vẫn gắn High vì `data` do caller đưa vào, nhưng sau sửa chỉ owner gọi được (`onlyOwner`, theo `msg.sender`) và đích là `module` immutable nên người ngoài không chọn được code thực thi. `weak-prng` ở `displayDay` cũng tương tự (High nhưng không ảnh hưởng tiền).
- Bằng chứng: `git diff` giữa commit `64b9776` và `b996a46` (xem `git_history.txt`), `evidence/before_raw` so với `evidence/after_raw`. Cảnh báo còn lại sau sửa chỉ là Low/Informational: `events-access` (updateOwner chưa emit event), `low-level-calls` (call/delegatecall có chủ đích) và `naming-convention` (tên `TipJar_0534` theo mẫu của đề).
- Lý do của mọi `slither-disable-next-line`:
  - `controlled-delegatecall` ở `plugin`: chỉ owner gọi; đích là module immutable đặt lúc deploy nên caller không chọn được; `data` chỉ chọn hàm trong module tin cậy.
  - `incorrect-equality` ở `vaultDrained`: view thuần, không dùng làm điều kiện chuyển tiền, ép gửi ETH chỉ làm kết quả hiển thị sai.
  - `weak-prng` ở `displayDay`: chỉ tính thứ trong tuần để hiển thị, không là nguồn ngẫu nhiên.
- Thành thật về quá trình: lần sửa đầu (commit `2f6db85`) CI vẫn RED vì `controlled-delegatecall` chưa suppress; lần hai (`b996a46`) GREEN.

## 3. Kiến trúc / Inheritance (1,5 điểm)

- Lệnh printer đã chạy: `python tools/print_arch.py` (human-summary và inheritance-graph trên `contracts/ArchitectureDemo.sol`). Script không tự tìm thấy file `.dot` do Slither đặt tên `ArchitectureDemo.sol.inheritance-graph.dot`, nên em copy file vào `evidence/architecture/` và chạy `dot -Tpng` thủ công.
- Ảnh: `evidence/architecture/inheritance.png` (đính kèm ảnh đã khoanh 3 node).
- Access control nằm ở `AccessManaged` (biến `admin`, modifier `onlyAdmin`); logic số dư nằm ở `BalanceLedger` (mapping `balances`, `_credit`, `balanceOf`); contract triển khai/entrypoint là `StudentAsset` (kế thừa cả hai, hàm `mint`).
- Giải thích: `StudentAsset` là điểm vào duy nhất cho bên ngoài (human-summary chỉ liệt kê nó với 4 hàm), nên auditor bắt đầu từ `mint(address,uint256)`. Hàm này chịu kiểm soát bởi `onlyAdmin` kế thừa từ `AccessManaged`, và gọi `_credit` của `BalanceLedger` để thay đổi `balances`. Đồ thị cho thấy quyền (mũi tên 1) và số dư (mũi tên 2) được tách thành hai contract riêng, nên cần kiểm tra `admin` được gán đúng trong constructor và `_credit` chỉ được gọi từ luồng đã qua `onlyAdmin`. Summary báo 1 optimization issue, 0 High/Medium.

## 4. Red -> Green CI (2,5 điểm)

| Phase | Commit (full/short SHA) | Run URL | Kết quả | Detector khiến RED / lý do GREEN |
|---|---|---|---|---|
| Baseline vulnerable | 64b977633b7bed741543588a2790d8a3f4d850b8 (64b9776) | https://github.com/hoanghipp-7/nt547-lab06-25520534/actions/runs/44739645202 | RED | Slither báo High/Medium: reentrancy-eth, controlled-delegatecall, tx-origin, unchecked-lowlevel, weak-prng, incorrect-equality |
| Patched | b996a46e11cdf472eebb3ddff049070fe117935b (b996a46) | https://github.com/hoanghipp-7/nt547-lab06-25520534/actions/runs/44741282313 | GREEN | Slither "0 result(s) found" ở mức High/Medium sau khi sửa 4 lỗi và suppress có lý do 3 vị trí |

- Local `--fail-none` chỉ thu thập finding và luôn thoát mã 0 (`process_exit_code: 0`); CI dùng `fail-on: medium` nên fail khi còn High/Medium. Vì thế local không đỏ dù có finding, còn CI đỏ.
- `exclude_low`/`exclude_informational` chỉ làm ẩn Low/Informational khỏi kết quả hiển thị, không ảnh hưởng gate vì gate chỉ xét Medium trở lên.

## 5. Mutation RED -> GREEN (1,5 điểm)

- Mutation theo đề: `require(msg.sender == owner, "not owner")` -> `require(tx.origin == owner, "not owner")` trong `modifier onlyOwner`. Em làm đúng theo đề trước, hai lần (commit `cc9c5b6` run #8 và `90e898f` run #5), cả hai CI vẫn GREEN. Chạy Slither local với đúng mutation đó cho kết quả không có `tx-origin`, chỉ còn Low/Informational. Kết luận: Slither 0.11.6 với detector `tx-origin` không báo `tx.origin` đặt trong modifier.
- Mutation thay thế (1 dòng): trong `updateOwner`, thay `require(newOwner != address(0), "zero");` bằng `require(tx.origin == owner, "not owner");`. Detector kỳ vọng `tx-origin` (Medium); xác nhận từ CI: run #7 FAIL ở step Slither, log có `Detector: tx-origin` (đính kèm ảnh log).

| Phase | Commit SHA | Run URL | Kết quả |
|---|---|---|---|
| Mutation | 8afe61b506dd612837b0e2618e1b217fbf71fe7a | https://github.com/hoanghipp-7/nt547-lab06-25520534/actions/runs/44743053343 | RED |
| Revert mutation | 9a584b088e76c1465b870f0de7a9c940ee06c1fd | https://github.com/hoanghipp-7/nt547-lab06-25520534/actions/runs/44743534498 | GREEN |

- Giải thích: `msg.sender` là địa chỉ gọi trực tiếp hàm, còn `tx.origin` là địa chỉ ví khởi tạo giao dịch ban đầu. Dùng `tx.origin` cho authorization cho phép contract trung gian hành động thay owner khi owner bị lừa gọi nó (phishing), vì `tx.origin` vẫn là owner. Dùng `msg.sender` đảm bảo chỉ chính địa chỉ gọi trực tiếp mới được xác thực.
- Lưu ý: dòng bị thay trong mutation là check `address(0)`; commit đã được revert nên mã cuối về trạng thái an toàn.

## 6. Bằng chứng, tự kiểm

- [x] `AuditTarget.sol`, `lab_identity.json`
- [x] `evidence/before_raw/` và `evidence/before_configured/`
- [x] `evidence/after_raw/` và `evidence/after_configured/` (đã quét lại sau khi suppress)
- [x] `evidence/architecture/`
- [x] 04 URL Actions run RED/GREEN/RED/GREEN + 04 commit SHA
- [x] Link repo và ảnh màn hình có terminal / URL / commit SHA; không cắt mất ngữ cảnh
- [x] Các finding được triage, không chép lại mô tả detector thay cho suy luận
- [x] Không có seed phrase, private key, credentials (token GitHub đã xoá sau khi nộp)

**Nhận xét cuối cùng:** Lab cho thấy Slither phát hiện tốt các mẫu lỗi quen thuộc như reentrancy, tx-origin và delegatecall, nhưng severity không luôn phản ánh risk thực tế: `controlled-delegatecall` vẫn bị báo sau khi đã có `onlyOwner` và module immutable, nên cần triage thủ công và suppress có lý do thay vì tắt detector. Quá trình RED/GREEN cũng cho thấy CI là cổng kiểm soát khách quan, vì lần sửa đầu của em vẫn bị chặn. Phần mutation cho thấy công cụ có giới hạn: đặt `tx.origin` trong modifier thì Slither 0.11.6 không báo, nên GREEN không có nghĩa là an toàn, và static analysis cần đi kèm code review. Em cũng tự phát hiện script `print_arch.py` không tìm đúng tên file `.dot` và xử lý bằng cách render thủ công với Graphviz. Kết quả cuối cùng là `main` ở trạng thái GREEN với 4 trạng thái RED, GREEN, RED, GREEN đã ghi đủ SHA và URL.
