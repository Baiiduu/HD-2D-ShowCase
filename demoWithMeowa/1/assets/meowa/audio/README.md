# 探索 BGM 与轻微风声

当前四境共用一首空灵探索音乐，以柔和钢琴、轻电子铺底、少量古筝和木笛音色连接街区、霓虹、庭院与林地。音乐按纯器乐要求制作，天气声音由 Weather 独立播放。

## 文件

| 文件 | 用途 | 来源 |
| --- | --- | --- |
| `bgm.mp3` | 当前 180 秒探索 BGM，原始下载文件 | Meowa Music，Pro，`job_7a4d36f7c937404390a98b8cf6e0c66a` |
| `wind.wav` | 当前 10 秒循环轻风，降低轰鸣与尖锐高频，控制响度 | 基于下方 Meowa 风声本地处理 |
| `wind_source.mp3` | 原始风声，保留 | Meowa Sound Effects，`job_cdbef3bc76d845659de419c4bdf415ab` |
| `bgm_rainy.mp3` | 首版音乐，包含生成器设计的雨声底纹，保留归档 | Meowa Music，Pro，`job_261574c790b84e9793fef6c6059e7972` |

风声的处理参数与校验值在 `wind-processing.json`。本地交付清单明确区分 Meowa 原始产物与本地处理或录音的文件。

## Godot 配置

主场景新增 **BGM → 背景音乐**：

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| Music Enabled | 开 | BGM 独立开关，关闭时淡出 |
| Music Stream | `bgm.mp3` | 可替换音乐资源；仅游戏运行时播放 |
| Music Volume Db | −20 dB | 音乐播放增益；更负的值更轻 |
| Music Fade Time | 3 秒 | 开关音乐时从静音到满音量的过渡时间 |
| Music Loop Crossfade | 6 秒 | 音乐末尾与开头交叉淡化的时间，避免硬切；短素材自动缩短 |
| Music Bus | Master | 项目中的已有音频总线；名称不存在时使用 Master |

**Weather → 轻微风声**：

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| Wind Audio Enabled | 开 | 风声音效独立开关，关闭后花草风摆继续生效 |
| Wind Sound | `wind.wav` | 可替换循环风声资源 |
| Wind Volume Db | −16 dB | 风力达到 3 时的音量；当前风力 1.65、雨量 0.7 时实际增益约 −18.16 dB |
| Wind Audio Fade Time | 3 秒 | 风声随风力或开关变化时的过渡时间 |
| Wind Audio Bus | Master | 项目中的已有音频总线；名称不存在时使用 Master |

风声音量跟随现有 Wind Strength 与 Rain Wind Boost。停雨后仍可有轻风；Wind Strength 为 0 且没有雨天增风时，风声淡出停止。关闭花草风摆总开关或天气总开关也会淡出风声；BGM 独立播放。

MP3、Ogg、WAV 都可作为音乐或风声资源。运行时使用副本设置播放方式，保留源资源；BGM 使用两路交叉淡化，风声使用整段循环。

在本地 Inspector 修改后按 Ctrl+S 保存；Remote 的调整只影响当前运行。编辑器不自动播放音频，重新运行游戏可听到保存后的设置。

完整实际请求及返回见 [HD 2D Meowa 调用记录](https://chatgpt.com/space/page_a1d8b19baf7c8191913c59c3b647e390) 的“8 制作探索音乐与轻风”。

## 试听与验证

- [BGM 单独试听](../../../../../docs/audio-preview/bgm.wav)：从旋律段选取 20 秒，使用当前 −20 dB 播放增益。
- [当前游戏混音](../../../../../docs/audio-preview/soundscape.wav)：18 秒实机录音，包含 BGM、细雨与轻风。
- [循环交叉淡化试听](../../../../../docs/audio-preview/music-loop.wav)：实机末尾到开头的 9 秒录音。

音乐实际长度约 179.64 秒，已通过原生 Godot 完整播放一轮；风声已连续播放两轮。音乐循环交叉淡化、停雨保留音乐与风声、无风时停止风声、独立开关、音量即时更新及编辑器不创建音频播放器均通过检查。生成源音乐、混音与循环录音没有削波样本；当前混音与循环录音没有静音断层。详细数值见 `audio-validation.json`。音乐风格与相对音量仍以你的试听为准。
