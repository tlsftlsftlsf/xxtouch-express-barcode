-- ==============================================================================
-- 脚本名称: BatchBarcodeExport.lua
-- 项目说明: XXTouch 屏幕快递单号批量识别与 CODE128 标准条码相册导出
-- 模式: 方案 B 全量批量静默导出 (已彻底阻断中文字符干扰 + 异常全透出)
-- 适用环境: XXTouch / XXTouch Elite (iOS)
-- 编码格式: UTF-8 (无 BOM)
-- ==============================================================================

screen.init(0)
nLog("========== 开始批量提取单号并导出标准条形码 ==========")

-- ==============================================================================
-- 1. 正则过滤：精准提取当前屏幕真实快递单号
-- ==============================================================================
local function extract_all_express_numbers(texts)
    local results = {}
    local seen = {}

    for _, text in ipairs(texts) do
        -- 严格使用 [A-Za-z0-9]，绝不匹配任何中文或高位 UTF-8 字节
        for token in text:gmatch("[A-Za-z0-9]+") do
            local len = #token
            if len >= 10 and len <= 18 then
                -- 1. 统计其中的数字个数：真实快递单号至少含 6 位以上数字 (排除纯英文 UI 词汇)
                local _, digit_count = token:gsub("%d", "")
                
                if digit_count >= 6 then
                    -- 2. 排除 11 位手机号 (1[3-9] 开头纯数字)
                    local is_phone = (len == 11 and token:match("^1[3-9]%d%d%d%d%d%d%d%d%d$") ~= nil)
                    -- 3. 排除 18 位身份证 (17 位数字 + 1 位数字/X)
                    local is_id_card = (len == 18 and token:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d[%dXx]$") ~= nil)

                    if not is_phone and not is_id_card then
                        if not seen[token] then
                            seen[token] = true
                            table.insert(results, token)
                        end
                    end
                end
            end
        end
    end
    return results
end

-- ==============================================================================
-- 2. CODE128 Auto 标准编码引擎 (带防呆保护)
-- ==============================================================================
local PATTERNS = {
    "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
    "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
    "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
    "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
    "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
    "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
    "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
    "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
    "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
    "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
    "114131", "311141", "411131", "211412", "211214", "211232", "2331112"
}

local function encode_code128_auto(text)
    -- 字符合法性前置检查
    for i = 1, #text do
        local b = text:byte(i)
        if b < 32 or b > 126 then
            return nil, "包含非 ASCII 可打印字符"
        end
    end

    local codes = {}
    local is_numeric = text:match("^%d+$") ~= nil

    if is_numeric and #text >= 2 then
        table.insert(codes, 105) -- Start C
        local pairs_count = math.floor(#text / 2)
        for i = 1, pairs_count do
            local start_i = (i - 1) * 2 + 1
            table.insert(codes, tonumber(text:sub(start_i, start_i + 1)))
        end
        if #text % 2 ~= 0 then
            table.insert(codes, 100) -- Switch to B
            local last_ch = text:sub(#text, #text)
            table.insert(codes, last_ch:byte() - 32)
        end
    else
        table.insert(codes, 104) -- Start B
        for i = 1, #text do
            table.insert(codes, text:byte(i) - 32)
        end
    end

    -- 校验和 (模 103)
    local sum = codes[1]
    for i = 2, #codes do
        sum = sum + (i - 1) * codes[i]
    end
    table.insert(codes, sum % 103)
    table.insert(codes, 106) -- Stop

    -- 转换为点阵数组
    local bits = {}
    for _, code in ipairs(codes) do
        local pat = PATTERNS[code + 1]
        if not pat then
            return nil, "未找到对应条码特征模式: " .. tostring(code)
        end
        local is_bar = true
        for j = 1, #pat do
            local w = tonumber(pat:sub(j, j))
            for _ = 1, w do
                table.insert(bits, is_bar and 1 or 0)
            end
            is_bar = not is_bar
        end
    end
    return bits
end

-- ==============================================================================
-- 3. 按照参考图样式绘制并导出图片 (纯白底色 + 1024×400 黄金比例)
-- ==============================================================================
local function export_barcode_image(bits, tracking_no)
    local module_w     = 6       -- 单元点宽度 (6px)
    local bar_h        = 225     -- 条形码高度
    local gap          = 34      -- 条码底部与文字间距
    local margin_top   = 60      -- 顶部留白
    local margin_bot   = 55      -- 底部留白
    local font_size    = 32.0    -- 底部文字字号

    local barcode_w = #bits * module_w
    local margin_x = math.max(100, math.floor((1024 - barcode_w) / 2))
    local total_w = barcode_w + margin_x * 2

    -- 纯白背景渲染文字 (杜绝黑框)
    local text_img = image.new_text_image(tracking_no, {
        font = "Helvetica",
        size = font_size,
        color = 0x222222,
        back_color = 0xffffff,
        back_alpha = 255
    })

    local text_w, text_h = 0, 28
    if text_img then
        text_w, text_h = text_img:size()
    end

    local total_h = margin_top + bar_h + gap + text_h + margin_bot

    local canvas = image.new(total_w, total_h)
    if not canvas then
        if text_img then text_img:destroy() end
        return false, "创建画布失败"
    end

    -- 涂纯白底色
    for y = 0, total_h - 1 do
        for x = 0, total_w - 1 do
            canvas:set_color(x, y, 0xffffff)
        end
    end

    -- 绘制条形码 (黑色)
    for i, bit in ipairs(bits) do
        if bit == 1 then
            local sx = margin_x + (i - 1) * module_w
            for bx = 0, module_w - 1 do
                local cur_x = sx + bx
                for cur_y = margin_top, margin_top + bar_h - 1 do
                    canvas:set_color(cur_x, cur_y, 0x000000)
                end
            end
        end
    end

    -- 居中贴上文字
    if text_img then
        local text_left = math.floor((total_w - text_w) / 2)
        local text_top = margin_top + bar_h + gap
        canvas:draw_image(text_img, { left = text_left, top = text_top })
        text_img:destroy()
    end

    canvas:save_to_album()
    canvas:destroy()
    return true
end

-- ==============================================================================
-- 4. 批量主逻辑 (单项容错 + 完整异常捕获)
-- ==============================================================================
local function main()
    nLog("正在 OCR 识别屏幕文本...")
    local texts = screen.ocr_text {}
    if not texts or #texts == 0 then
        nLog("屏幕未识别到任何文本内容")
        return
    end

    local list = extract_all_express_numbers(texts)
    if #list == 0 then
        nLog("屏幕未发现有效快递单号")
        return
    end

    nLog(string.format("识别到 %d 个单号，开始批量生成并导出...", #list))

    -- 复制所有单号到剪贴板
    pasteboard.write(table.concat(list, "\n"))

    -- 逐个生成，单项增加独立保护
    local success_count = 0
    for idx, no in ipairs(list) do
        local ok, err = pcall(function()
            local bits, enc_err = encode_code128_auto(no)
            if not bits then
                error(enc_err or "编码点阵失败")
            end
            local saved, save_err = export_barcode_image(bits, no)
            if not saved then
                error(save_err or "相册保存失败")
            end
        end)

        if ok then
            success_count = success_count + 1
            nLog(string.format("[%d/%d] 已导出单号: %s", idx, #list, no))
        else
            nLog(string.format("[%d/%d] 单号 %s 导出失败，原因: %s", idx, #list, no, tostring(err)))
        end

        sys.sleep(0.15) -- 留出足够的相册写入时间
    end

    nLog(string.format("========== 批量导出结束：成功 %d / %d ==========", success_count, #list))
    sys.toast(string.format("批量导出完成：成功 %d 个", success_count))
end

-- 全局异常拦截，发生错误必打印
local ok, err = xpcall(main, debug.traceback)
if not ok then
    nLog("【脚本严重错误中断】: " .. tostring(err))
end
