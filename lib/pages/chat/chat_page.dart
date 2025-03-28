import 'package:ai_client/common/utils/chat_http.dart';
import 'package:ai_client/database/app_database.dart';
import 'package:ai_client/generated/locale_keys.dart';
import 'package:ai_client/models/chat_message.dart';
import 'package:ai_client/pages/chat/input.dart';
import 'package:ai_client/pages/chat/message_list.dart';
import 'package:ai_client/pages/settings/apis/api_info.dart';
import 'package:ai_client/repositories/ai_api_repository.dart';
import 'package:ai_client/services/ai_api_service.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// 聊天页面，同时集成了 HTTP 请求和 SQLite 加载 API 配置信息
class ChatPage extends StatefulWidget {
  // 添加构造函数，接收 key 参数s
  const ChatPage({super.key});

  @override
  ChatPageState createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  // 消息列表
  List<ChatMessageInfo> _messages = [];

  // 消息输入框控制器
  TextEditingController _messageController = TextEditingController();

  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

  // 使用 ChatHttp 调用 OpenAI 接口
  final ChatHttp _chatHttp = ChatHttp();

  // 数据源
  late final AppDatabase _appDatabase;

  /// AiApi 服务类
  late final AiApiService _aiApiService;

  // 加载到的 API 配置列表
  late List<AiApiData> _apiConfig;

  // 当前正在使用的 API 配置
  AiApiData? _currentApi;

  // 当前模型列表
  List<String> _models = [];

  // 当前选择的 模型
  String _currentModel = "";

  // 是否正在等待回复
  bool _isWaitingResponse = false;

  // 是否使用流式请求
  bool _useStream = false;

  @override
  void initState() {
    super.initState();
    // 初始化数据源
    _appDatabase = AppDatabase();
    // 初始化 AiApi 服务类
    _aiApiService = AiApiService(AiApiRepository(_appDatabase));
    // 初始化 API 配置
    _loadApiConfig();
  }

  /// 显示通用提示弹窗
  void _showAlertDialog(String title, String content) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: Text(tr(LocaleKeys.confirm)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // 从 SQLite 数据库中加载 API 配置信息，优先取第一条记录
  Future<void> _loadApiConfig() async {
    final apis = await _aiApiService.initDefaultAiApiConfig();
    if (apis.isNotEmpty) {
      setState(() {
        // 设置 API 配置列表
        _apiConfig = apis;
      });
    } else {
      _showAlertDialog('提示', '未找到 API 配置信息');
    }
  }

  /// 聊天页信息设置弹窗
  void _showSettingsDialog() async {
    // 重新加载API配置并等待完成
    await _loadApiConfig();

    // 如果组件已卸载，则不继续执行
    if (!mounted) return;

    // 如果API配置为空，提示用户
    if (_apiConfig.isEmpty) {
      _showAlertDialog('提示', '无可用 API 配置信息');
      return;
    }

    // 判断当前API是否为空
    if (_currentApi == null) {
      // 如果当前API为空，设置为第一个API
      _currentApi = _apiConfig[0];
    } else {
      // 如果选择了则比对是否当前选择的API信息已经发生变化
      final currentApiIndex =
          _apiConfig.indexWhere((api) => api.id == _currentApi!.id);
      if (currentApiIndex == -1) {
        // 如果当前选择的API不在配置列表中，重置为第一个API
        _currentApi = _apiConfig[0];
      } else {
        // 更新当前API的信息
        _currentApi = _apiConfig[currentApiIndex];
      }
    }

    // 初始化模型列表
    List<String> currentModels = _currentApi!.models.split(',');

    // 初始化当前模型（如果未设置或不在当前模型列表中）
    if (_currentModel.isEmpty || !currentModels.contains(_currentModel)) {
      _currentModel = currentModels.isNotEmpty ? currentModels[0] : "";
    }

    // 创建临时变量用于对话框中的选择
    AiApiData tempSelectedApi = _currentApi!;
    String tempSelectedModel = _currentModel;
    bool tempUseStream = _useStream;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          // 根据选择的API更新模型列表
          List<String> modelOptions = tempSelectedApi.models.split(',');

          // 确保选择的模型在当前API的模型列表中
          if (!modelOptions.contains(tempSelectedModel) &&
              modelOptions.isNotEmpty) {
            tempSelectedModel = modelOptions[0];
          }

          return AlertDialog(
            title: Text(''),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // API和模型选择标题
                  Row(
                    children: [
                      Expanded(
                        child: Text(LocaleKeys.aiApiModelConfig,
                                style: TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center)
                            .tr(),
                      ),
                      Expanded(
                        child: Text(LocaleKeys.aiApiModelModels,
                                style: TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center)
                            .tr(),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  // API和模型选择列表
                  SizedBox(
                    height: 200, // 设置一个固定高度
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // API列表（左侧）
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _apiConfig.length,
                              itemBuilder: (context, index) {
                                var api = _apiConfig[index];
                                return ListTile(
                                  title: Text(api.serviceName),
                                  subtitle: Text(
                                    api.baseUrl,
                                    style: TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  selected: tempSelectedApi.id == api.id,
                                  // 单击事件
                                  onTap: () {
                                    setState(() {
                                      tempSelectedApi = api;
                                      // 更新模型列表并选择第一个模型
                                      List<String> newModels =
                                          api.models.split(',');
                                      tempSelectedModel = newModels.isNotEmpty
                                          ? newModels[0]
                                          : "";
                                    });
                                  },
                                  // 长按事件
                                  onLongPress: () async {
                                    // 长按时 通过弹窗打开 API 详情页面
                                    final result = await showDialog(
                                      context: context,
                                      builder: (context) => ApiInfo(
                                        aiApi: api,
                                        appDatabase: _appDatabase,
                                      ),
                                    );

                                    // 如果组件已卸载，则不继续执行
                                    if (!mounted) return;

                                    // 判断返回结果
                                    if (result == true) {
                                      // 根据当前选择的API信息查询新的API信息
                                      final newApi = await _aiApiService
                                          .getAiApiById(api.id);

                                      if (newApi != null) {
                                        // 更新对应的 API 信息
                                        setState(() {
                                          // 查找当前修改的API在列表中的索引
                                          final apiIndex =
                                              _apiConfig.indexWhere(
                                                  (item) => item.id == api.id);

                                          // 如果找到了，更新列表中的API信息
                                          if (apiIndex != -1) {
                                            _apiConfig[apiIndex] = newApi;

                                            // 如果当前选中的就是被修改的API，也更新当前选中的API
                                            if (tempSelectedApi.id == api.id) {
                                              tempSelectedApi = newApi;
                                            }

                                            // 更新本地变量，确保UI刷新
                                            api = newApi;
                                          }
                                        });
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        // 模型列表（右侧）
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: modelOptions.length,
                              itemBuilder: (context, index) {
                                final model = modelOptions[index];
                                return ListTile(
                                  title: Text(model),
                                  selected: tempSelectedModel == model,
                                  onTap: () {
                                    setState(() {
                                      tempSelectedModel = model;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: Text(tr(LocaleKeys.cancel)),
                onPressed: () {
                  // 关闭弹窗
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(tr(LocaleKeys.save)),
                onPressed: () {
                  // 保存选择的API和模型
                  this.setState(() {
                    _currentApi = tempSelectedApi;
                    _currentModel = tempSelectedModel;
                    _useStream = tempUseStream;
                  });
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });
      },
    );
  }

  /// 滚动到最底部
  void _scrollToBottom() {
    // 添加短暂延迟，确保布局已更新
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 发送消息
  Future<void> _sendMessage() async {
    // 判断输入框是否为空 或者 正在等待回复
    if (_isWaitingResponse || _messageController.text.isEmpty) return;

    // 判断是否有可用 API 配置信息
    if (_apiConfig.isEmpty) {
      _showAlertDialog('提示', '无可用 API 配置信息');
      return;
    }

    // 当前没有 API 配置信息时，默认使用第一条
    _currentApi ??= _apiConfig[0];

    // 加载模型列表
    _models = _currentApi!.models.split(',');

    // 当前没有模型时，默认使用第一条
    if (_currentModel.isEmpty) {
      _currentModel = _models.isNotEmpty ? _models[0] : "";
    }

    // 存储一个新的消息列表 防止历史消息被覆盖
    List<ChatMessageInfo> newMessages = List.from(_messages);

    final userMessage = _messageController.text;
    setState(() {
      _messages.add(ChatMessageInfo(
          content: userMessage,
          isUser: true,
          modelName: _currentModel,
          createdTime: DateTime.now()));
      _messageController.clear();
      _isWaitingResponse = true; // 设置等待状态
    });
    // 滚动到最底部
    _scrollToBottom();

    // 默认加载中
    final aiMessage = ChatMessageInfo(
        content: tr(LocaleKeys.chatPageThinking),
        isUser: false,
        modelName: _currentModel,
        createdTime: DateTime.now());
    setState(() {
      _messages.add(aiMessage);
    });

    try {
      if (_useStream) {
        // 流式请求处理
        final responseStream = await _chatHttp.sendStreamChatRequest(
            api: _currentApi!,
            model: _currentModel,
            message: userMessage,
            historys: newMessages);

        // 用于累积AI回复的内容
        String accumulatedContent = "";

        // 处理流
        responseStream.listen((content) {
          // 累积内容
          accumulatedContent += content;

          // 更新消息内容
          setState(() {
            aiMessage.content = accumulatedContent;
          });
          // 滚动到最底部
          _scrollToBottom();
        }, onDone: () {
          // 流结束时的处理
          setState(() {
            _isWaitingResponse = false; // 清除等待状态
          });
          // 滚动到最底部
          _scrollToBottom();
        }, onError: (error) {
          // 错误处理
          setState(() {
            aiMessage.content = "发生错误: $error";
            _isWaitingResponse = false; // 清除等待状态
          });
          // 滚动到最底部
          _scrollToBottom();
        });
      } else {
        // 非流式请求处理
        final response = await _chatHttp.sendChatRequest(
            api: _currentApi!,
            model: _currentModel,
            message: userMessage,
            historys: newMessages);

        // 从响应中提取内容
        final content =
            response.data['choices'][0]['message']['content'] as String;

        // 更新消息内容
        setState(() {
          aiMessage.content = content;
          _isWaitingResponse = false; // 清除等待状态
        });
        // 滚动到最底部
        _scrollToBottom();
      }
    } catch (e) {
      // 控制台打印错误信息
      print('请求出错: $e');
      // 出错时，显示错误信息
      String errorMessage = '请求出错';
      if (e is DioException && e.response != null) {
        errorMessage =
            '请求出错: 状态码 ${e.response!.statusCode} - ${e.response!.data}';
      } else {
        errorMessage = '请求出错: $e';
      }
      setState(() {
        // 找到加载消息的索引并替换它
        final loadingIndex = _messages.indexOf(aiMessage);
        if (loadingIndex != -1) {
          _messages[loadingIndex] = ChatMessageInfo(
              content: errorMessage,
              isUser: false,
              modelName: _currentModel,
              createdTime: DateTime.now());
        }
        _isWaitingResponse = false; // 清除等待状态
      });
    }
  }

  /// 清除聊天记录
  void clearChat() {
    // 确保只有在组件已挂载时才调用 setState
    if (mounted) {
      setState(() {
        _messages.clear();
      });
    } else {
      // 如果组件未挂载，直接清空消息列表
      _messages.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度，用于判断是否为桌面端
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 600;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部工具栏
            if (!isDesktop)
              Container(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 左侧设置按钮
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: Colors.grey.shade300, width: 1),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.settings, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                        onPressed: () {
                          _showSettingsDialog();
                        },
                      ),
                    ),
                    // 中间标题
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.smart_toy_outlined,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          _currentModel.isNotEmpty ? _currentModel : 'AI Chat',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    // 右侧新对话按钮
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: Colors.grey.shade300, width: 1),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.add, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                        onPressed: () {
                          clearChat();
                        },
                        tooltip: tr(LocaleKeys.chatPageNewChat),
                      ),
                    ),
                  ],
                ),
              ),
            // 桌面端顶部工具栏
            if (isDesktop)
              Padding(
                padding: EdgeInsets.only(top: 16, left: 16, right: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          _currentModel.isNotEmpty ? _currentModel : 'AI Model',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: Icon(Icons.settings, size: 18),
                          onPressed: () {
                            _showSettingsDialog();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            // 消息内容区 - 桌面端时增加内边距
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 0),
                child: MessageList(
                  messages: _messages,
                  scrollController: _scrollController,
                ),
              ),
            ),
            // 输入框 - 桌面端时增加内边距和样式
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 16 : 0, vertical: isDesktop ? 16 : 0),
              child: InputWidget(
                messageController: _messageController,
                isWaitingResponse: _isWaitingResponse,
                onSendMessage: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
