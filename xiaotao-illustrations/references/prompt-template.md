# Prompt 模板 · Shot List + 生图 + 字体方案

> 分三层：**Shot List 规划模板** + **单图生图 Prompt 模板** + **字体与文字渲染方案**。

## 1. Shot List 规划模板

读入文章后，为每张配图输出结构化 shot。每项填写要求：

```markdown
### Shot {N}
- **放置位置**：第{X}段之后，承接"{核心句子}"
  ↑ 必须引用原文原句，不能凭记忆概括
- **主题**：{一句话概括这张图在说什么}
- **核心认知锚点**：{这张图要把文章里哪个判断/结构/状态画出来}
  ↑ 锚点要具体到"可以证伪"的程度：说清变化的是什么、方向是什么、涉及几个对象
- **构图类型**：{Workflow/系统局部/前后对比/角色状态/概念隐喻/方法分层/地图路线/小漫画分镜}
- **隐喻设计**：{用什么编程/技术场景来隐喻这个概念}
  ↑ 隐喻逻辑链要写全：A（概念）↔ B（画面物），对应关系一句话说清；
    画面的结构关系（几层/几步/几个对象）必须与概念的逻辑关系一一对应
- **小桃动作**：{小桃具体在做什么动作，什么表情}
  ↑ 动作必须是隐喻里的关键操作，不是旁观
- **中文标注建议**：{2-4个短词}
  ↑ 标注词优先从原文提取原词；中文短词或代码等宽感英文
- **画面关键词**：{3-5个视觉关键词}
  ↑ 用于组装生图 prompt 的 [本图内容] 段
```

**Shot List 输出后必须先经用户确认**，再进入生图。

## 2. 单图生图 Prompt 模板

模板分四段，组装时按顺序拼接为一段完整英文 prompt（内部可夹中文标注词）。

```text
[角色锁定]
（逐字复用 references/character-ip.md 的角色锁定段）

[风格锁定]
（逐字复用 references/style-dna.md 的风格锁定段）

[本图内容]
Composition type: {composition_type}
Metaphor: {metaphor_description with exact structural correspondence:
    number of steps/layers/objects must match the concept's logic}
XiaoTao is {action_description}, with {relaxed/precise expression}.
Key objects: {objects, keep to one core object/action}
Tech elements: {terminals, architecture blocks, code screens — simplified
    but structurally correct}
Label placeholders: {2-4 short Chinese words or monospace English terms,
    in brown or red ink, handwriting style}

[负面约束]
No pure black outlines, no dark or heavily saturated colors,
no flat cel-shading, no 3D rendering, no gothic/dark style,
no overcrowded composition, no floating decorative stickers or doodle icons,
no childish cartoon style, no large title text, no realistic proportions,
no standing pose doing nothing, no overly sweet baking/garden aesthetic,
no hyper energetic pose, no frilly decorations.
```

### 各段填写细则

1. **[角色锁定]**：固定不变，逐字复用，不要增删改（防止角色漂移）
2. **[风格锁定]**：固定不变，逐字复用；"浅色水彩"（light watercolor）是第一关键词，放在最前
3. **[本图内容]**：唯一需要填写的段落。填写规则：
   - 隐喻描述必须写明**结构对应关系**（"3 步流程画成 3 站传送带"优于"流水线场景"）
   - 小桃的动作必须是完整动宾结构（"敲下最后一个键"优于"操作电脑"）
   - 标注词≤4个、每个≤6字，中文优先从原文提取原词
4. **[负面约束]**：固定不变，逐字复用

## 3. 字体与文字渲染方案（内置字体，不依赖用户本地环境）

**问题**：图像模型直接画中文极易错字、幻觉文字；如果靠用户本地字体做后处理，换台机器就缺字体。

**方案**：Skill 包内置开源字体文件 + 双层文字策略。

### 3.1 字体目录（assets/fonts/）

| 文件 | 用途 | 许可证 | 说明 |
|---|---|---|---|
| `LXGWWenKai-Regular.ttf`（霞鹜文楷） | 中文标注手写风字体 | SIL OFL 1.1（可自由分发） | 楷体手写感，与浅色水彩手账风天然匹配 |
| `JetBrainsMono-Regular.ttf` | 代码/等宽标注 | SIL OFL 1.1（可自由分发） | 代码标签、终端文字、英文等宽标注 |
| `OFL-Licenses.md` | 许可证文本 | — | 两个字体的许可证原文，随包分发合规 |

### 3.2 双层文字策略

1. **第一层（模型直绘）**：生图 prompt 中仅保留 2-4 个超短标注词，由模型直接画在图里。适合：英文代码词（BUG、COMMIT）、单字中文词。模型画短词出错率低。
2. **第二层（程序叠字）**：生图时在 prompt 中要求"留出标注区域、保持简洁"（风格锁定段已内置），生成后如需精确中文长词，用包内字体通过代码渲染叠加。

### 3.3 程序叠字规格

- 字体路径写死为 Skill 包内相对路径 `assets/fonts/`，**不引用任何系统字体**，保证任何机器上结果一致
- 中文标注：霞鹜文楷，棕色 `#8B5A3C` 或红色 `#C25450`
- 代码标注：JetBrains Mono，棕色或深灰
- 字号适中，可轻微旋转 2-5° 增加手写感
- 位置不遮挡小桃和核心物件

### 3.4 最小可用叠字代码（Python PIL）

```python
from PIL import Image, ImageDraw, ImageFont

# 字体路径：Skill 包内路径，禁止使用系统字体
FONT_CN = "assets/fonts/LXGWWenKai-Regular.ttf"       # 中文手写风
FONT_CODE = "assets/fonts/JetBrainsMono-Regular.ttf"  # 代码等宽

# 叠字颜色规格
BROWN = (139, 90, 60)    # #8B5A3C 棕色标注
RED = (194, 84, 80)      # #C25450 红色强调

def add_label(image_path, output_path, text, xy,
              color=BROWN, font_size=48, angle=3, font_path=FONT_CN):
    """在图上叠加手写风标注文字。
    xy: 文字左上角坐标 (x, y)
    angle: 轻微旋转角度（2-5 度增加手写感），0 为不旋转
    """
    img = Image.open(image_path).convert("RGBA")
    font = ImageFont.truetype(font_path, font_size)

    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.text(xy, text, font=font, fill=tuple(color) + (255,))

    if angle:
        layer = layer.rotate(angle, expand=False)

    out = Image.alpha_composite(img, layer)
    out.convert("RGB").save(output_path)

# 用法示例：
# add_label("shot-01.png", "shot-01-labeled.png", "三个断点", (120, 200),
#           color=BROWN, font_size=44, angle=3)
# add_label("shot-02.png", "shot-02-labeled.png", "git push", (880, 150),
#           color=RED, font_size=36, angle=0, font_path=FONT_CODE)
```

> 注意：运行前确认已安装 Pillow（`pip install Pillow`）。字体路径按 Skill 包实际安装位置解析为绝对路径。
