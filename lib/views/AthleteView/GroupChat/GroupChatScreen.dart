import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:us_rowing/models/GroupMessageModel.dart';
import 'package:us_rowing/network/ApiClient.dart';
import 'package:us_rowing/utils/AppColors.dart';
import 'package:us_rowing/utils/MySnackBar.dart';
import 'package:us_rowing/widgets/CachedImage.dart';
import 'package:us_rowing/widgets/GroupedListView.dart';
import 'package:us_rowing/widgets/PrimaryButton.dart';
import 'package:us_rowing/widgets/ZoomImage.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:us_rowing/network/response/MessagesResponse.dart';
import 'package:us_rowing/models/MessageModel.dart';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:us_rowing/utils/AppUtils.dart';
import 'package:us_rowing/network/MediaResponse.dart';
import 'dart:convert';

import '../../WorkoutDetail.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String currentUserId;
  final IO.Socket socket;
  final bool share;
  final String workoutId;
  final String workoutName;
  final String workoutImage;

  GroupChatScreen({
    required this.groupId,
    required this.currentUserId,
    required this.socket,
    required this.share,
    required this.workoutId,
    required this.workoutName,
    required this.workoutImage,
  });

  @override
  State createState() => new _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  List<MessageModel> listMessage = [];

  late File _image;
  late bool isLoading;
  late bool isShowSticker;
  late String imageUrl;
  bool uploading = false;

  final TextEditingController textEditingController =
      new TextEditingController();
  final ScrollController listScrollController = new ScrollController();
  final FocusNode focusNode = new FocusNode();

  @override
  void initState() {
    super.initState();

    print(widget.socket.connected);

    getChatList();

    widget.socket.on('group-message', (data) {
      print('Data: ' + data.toString());
      MessageModel newMessage = MessageModel.fromJson(data);
      if (this.mounted) {
        setState(() {
          listMessage.insert(0, newMessage);
        });
      }

      print('send message is got');
      print(data);
    });

    focusNode.addListener(onFocusChange);

    isLoading = false;
    isShowSticker = false;
    imageUrl = '';

    if (widget.share) {
      pendingShare().then((value) {
        if (value) {
          showBottomSheet();
        }
      });
    }
  }

  void onFocusChange() {
    if (focusNode.hasFocus) {
      // Hide sticker when keyboard appear
      setState(() {
        isShowSticker = false;
      });
    }
  }

  Future getImage(int index) async {
    // File selected = File(selectedFile.path);

    XFile? selectedFile;

    if (index == 0)
      selectedFile = await ImagePicker()
          .pickImage(source: ImageSource.gallery)
          .onError((error, stackTrace) {
        print("Error" + error.toString());

        return;
      });
    else
      selectedFile = await ImagePicker()
          .pickImage(source: ImageSource.camera)
          .onError((error, stackTrace) {
        print("Error" + error.toString());
        return;
      });

    _image = File(selectedFile!.path);
    uploadImage();
  }

  Future<bool> onBackPress() {
    Navigator.pop(context);
    return Future.value(false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // List of messages
              widgetChatBuildListMessage(listMessage, widget.currentUserId,
                  listScrollController, context),

              // Input content
              buildInput(),
            ],
          ),

          uploading
              ? Positioned(
                  top: 40,
                  left: 100,
                  right: 100,
                  child: Container(
                    padding: EdgeInsets.all(8.0),
                    color: colorBlack.withOpacity(0.5),
                    child: Center(
                        child: Text(
                      'Uploading Image',
                      style: TextStyle(color: colorWhite),
                    )),
                  ))
              : SizedBox(),

          // Loading
          buildLoading()
        ],
      ),
      onWillPop: onBackPress,
    );
  }

  Widget buildLoading() {
    return Positioned(
      child: isLoading
          ? Container(
              child: Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(colorBlue)),
              ),
              color: Colors.white.withOpacity(0.8),
            )
          : Container(),
    );
  }

  Widget buildInput() {
    return Container(
      child: Row(
        children: <Widget>[
          // Button send image
          Material(
            child: new Container(
              margin: new EdgeInsets.symmetric(horizontal: 1.0),
              child: new IconButton(
                icon: new Icon(Icons.image),
                onPressed: () => getImage(0),
                color: colorGrey,
              ),
            ),
            color: Colors.white,
          ),
          Material(
            child: new Container(
              margin: new EdgeInsets.symmetric(horizontal: 1.0),
              child: new IconButton(
                icon: new Icon(Icons.camera_alt),
                onPressed: () => getImage(1),
                color: colorGrey,
              ),
            ),
            color: Colors.white,
          ),
          // Edit text
          Flexible(
            child: Container(
              child: TextField(
                style: TextStyle(color: colorBlack, fontSize: 15.0),
                controller: textEditingController,
                decoration: InputDecoration.collapsed(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(color: colorGrey),
                ),
                focusNode: focusNode,
              ),
            ),
          ),

          // Button send message
          Material(
            child: new Container(
              margin: new EdgeInsets.symmetric(horizontal: 8.0),
              child: new IconButton(
                icon: new Icon(Icons.send),
                color: colorPrimary,
                onPressed: () {
                  String text = textEditingController.text;
                  if (text.isNotEmpty) {
                    sendMessage();
                  }
                },
              ),
            ),
            color: Colors.white,
          ),
        ],
      ),
      width: double.infinity,
      height: 50.0,
      decoration: new BoxDecoration(
          border: new Border(top: new BorderSide(color: colorGrey, width: 0.5)),
          color: Colors.white),
    );
  }

  static Widget widgetChatBuildListMessage(List<MessageModel> listMessage,
      currentUserId, listScrollController, BuildContext context) {
    return Flexible(
      child: GroupedListView(
        listBuilder: (context, MessageModel index) =>
            widgetChatBuildItem(context, index, currentUserId, '', ''),
        collection: listMessage,
        groupBy: (MessageModel element) => element.formattedLocalDate,
        groupBuilder: (BuildContext context, String date) => Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                date,
                style: TextStyle(color: colorGrey, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget widgetChatBuildItem(
    BuildContext context,
    MessageModel message,
    String id,
    String document,
    String peerAvatar,
  ) {
    if (message.messageType == 'img') {
      if (message.senderId == id) {
        return Row(
          children: <Widget>[
            chatImage(context, message, message.senderId != id)
          ],
          mainAxisAlignment: MainAxisAlignment.end,
        );
      } else {
        return Row(
          children: <Widget>[
            CachedImage(
              image: ApiClient.baseUrl + peerAvatar,
              imageHeight: 30,
              imageWidth: 30,
            ),
            SizedBox(
              width: 5,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderName,
                  style: TextStyle(color: colorGrey, fontSize: 10),
                ),
                chatImage(context, message, message.senderId != id),
              ],
            )
          ],
          mainAxisAlignment: MainAxisAlignment.start,
        );
      }
    } else if (message.messageType == 'workout' &&
        message.workoutId.isNotEmpty) {
      if (message.senderId == id) {
        return Row(
          children: <Widget>[
            chatWorkout(context, message, message.senderId != id)
          ],
          mainAxisAlignment: MainAxisAlignment.end,
        );
      } else {
        return Row(
          children: <Widget>[
            chatWorkout(context, message, message.senderId != id)
          ],
          mainAxisAlignment: MainAxisAlignment.start,
        );
      }
    } else {
      if (message.senderId == id) {
        return Row(
          children: <Widget>[
            Flexible(
                child: chatText(
                    message.body, id, message, message.senderId != id, context))
          ],
          mainAxisAlignment: MainAxisAlignment.end,
        );
      } else {
        return Row(
          children: <Widget>[
            CachedImage(
              image: ApiClient.baseUrl + peerAvatar,
              imageHeight: 30,
              imageWidth: 30,
            ),
            SizedBox(
              width: 5,
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.senderName,
                    style: TextStyle(color: colorGrey, fontSize: 10),
                  ),
                  chatText(message.body, id, message, message.senderId != id,
                      context)
                ],
              ),
            )
          ],
          mainAxisAlignment: MainAxisAlignment.start,
        );
      }
    }

    // if (index == 0) {
    //   return Row(
    //     children: <Widget>[chatText(message.body, id, message, index, true)],
    //     mainAxisAlignment: MainAxisAlignment.end,
    //   );
    // } else if (index == 1) {
    //   return Row(
    //     children: <Widget>[
    //       chatImage(context, id, message, 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/07/Heidi_Klum_by_Glenn_Francis.jpg/1200px-Heidi_Klum_by_Glenn_Francis.jpg', index, true)
    //     ],
    //     mainAxisAlignment: MainAxisAlignment.end,
    //   );
    // } else if (index == 2) {
    //   return Container(
    //     child: Column(
    //       children: <Widget>[
    //         Row(
    //           children: <Widget>[
    //             Material(
    //               child: widgetShowImages('https://upload.wikimedia.org/wikipedia/commons/thumb/0/07/Heidi_Klum_by_Glenn_Francis.jpg/1200px-Heidi_Klum_by_Glenn_Francis.jpg', 35),
    //               borderRadius: BorderRadius.all(
    //                 Radius.circular(18.0),
    //               ),
    //               clipBehavior: Clip.hardEdge,
    //             ),
    //             chatText(
    //                 'Hello', id, message, index, false)
    //           ],
    //         ),
    //
    //         // Time
    //         isLastMessageLeft(message, id, index)
    //             ? Container(
    //           child: Text(
    //             '2:23 PM',
    //             style: TextStyle(
    //                 color: colorGrey,
    //                 fontSize: 12.0,
    //                 fontStyle: FontStyle.italic),
    //           ),
    //           margin: EdgeInsets.only(left: 50.0, top: 5.0, bottom: 5.0),
    //         )
    //             : Container()
    //       ],
    //       crossAxisAlignment: CrossAxisAlignment.start,
    //     ),
    //     margin: EdgeInsets.only(bottom: 10.0),
    //   );
    // } else {
    //   return Container(
    //     child: Column(
    //       children: <Widget>[
    //         Row(
    //           children: <Widget>[
    //             Material(
    //               child: widgetShowImages('https://upload.wikimedia.org/wikipedia/commons/thumb/0/07/Heidi_Klum_by_Glenn_Francis.jpg/1200px-Heidi_Klum_by_Glenn_Francis.jpg', 35),
    //               borderRadius: BorderRadius.all(
    //                 Radius.circular(18.0),
    //               ),
    //               clipBehavior: Clip.hardEdge,
    //             ),
    //             chatImage(context, id, message,
    //                 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/07/Heidi_Klum_by_Glenn_Francis.jpg/1200px-Heidi_Klum_by_Glenn_Francis.jpg', index, false),
    //           ],
    //         ),
    //
    //         // Time
    //         isLastMessageLeft(message, id, index)
    //             ? Container(
    //           child: Text(
    //             '12-09-08 12:23 PM',
    //             style: TextStyle(
    //                 color: colorGrey,
    //                 fontSize: 12.0,
    //                 fontStyle: FontStyle.italic),
    //           ),
    //           margin: EdgeInsets.only(left: 50.0, top: 5.0, bottom: 5.0),
    //         )
    //             : Container()
    //       ],
    //       crossAxisAlignment: CrossAxisAlignment.start,
    //     ),
    //     margin: EdgeInsets.only(bottom: 10.0),
    //   );
    // }
  }

  static Widget chatWorkout(
      BuildContext context, MessageModel message, bool logUserMsg) {
    return Container(
      child: ElevatedButton(
        child: Material(
          child: widgetShowWorkout(
              message.body,
              message.workoutId,
              150,
              !logUserMsg,
              message.attachments.length == 0 ? '' : message.attachments[0],
              message),
          borderRadius: BorderRadius.all(Radius.circular(8.0)),
          clipBehavior: Clip.hardEdge,
        ),
        onPressed: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => WorkoutDetail(
                        workoutName: message.body,
                        workoutId: message.workoutId,
                        imgUrl: message.attachments.length == 0
                            ? ''
                            : message.attachments[0],
                      )));
        },
        // padding: EdgeInsets.all(0),
      ),
      margin: logUserMsg
          ? EdgeInsets.only(
              bottom: /*isLastMessageRight(listMessage, id, index) ? 20.0 :*/
                  20.0,
              right: 10.0)
          : EdgeInsets.only(left: 20.0, bottom: 10),
    );
  }

  static Widget widgetShowWorkout(String workoutName, String workoutId,
      double size, bool sent, String image, MessageModel message) {
    return Container(
      height: size / 2,
      width: size,
      decoration: BoxDecoration(
        color: sent ? colorChatPrimary : colorChatSecondary,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Stack(
        children: [
          CachedImage(
            imageHeight: size / 2,
            imageWidth: size,
            padding: 0,
            image: ApiClient.baseUrl + image,
            radius: 0,
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Workout',
                  style: TextStyle(
                      color: colorBlack,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    workoutName,
                    style: TextStyle(color: colorBlack),
                  ),
                ),
              )
            ],
          ),
          Positioned(
            bottom: 5,
            right: 5,
            child: Text(
              getTime(message.createdAt),
              style: TextStyle(fontSize: 10, color: colorGrey),
            ),
          )
        ],
      ),
    );
  }

  static Widget chatText(String chatContent, String id, MessageModel message,
      bool logUserMsg, BuildContext context) {
    return Container(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              chatContent,
              style: TextStyle(color: logUserMsg ? colorBlack : colorBlack),
            ),
          ),
          SizedBox(
            width: 3,
          ),
          Text(
            getTime(message.createdAt),
            style: TextStyle(
                fontSize: 10, color: logUserMsg ? colorGrey : colorGrey),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
      decoration: BoxDecoration(
          color: logUserMsg ? colorChatSecondary : colorChatPrimary,
          borderRadius: BorderRadius.circular(8.0)),
      margin: logUserMsg
          ? EdgeInsets.only(
              bottom: /*isLastMessageRight(listMessage, id, index) ? 20.0 :*/
                  10.0,
              right: 50.0)
          : EdgeInsets.only(left: 50.0, bottom: 10),
    );
  }

/*   static bool isLastMessageRight(var listMessage, String id, int index) {
    if ((index > 0 &&
        listMessage != null &&
        listMessage[index - 1].get('idFrom') != id) ||
        index == 0) {
      return true;
    } else {
      return false;
    }
  } */

  static Widget chatImage(
      BuildContext context, MessageModel message, bool logUserMsg) {
    return Container(
      child: ElevatedButton(
        child: Material(
          child: widgetShowImages(
              ApiClient.baseUrl + message.attachments[0], 150, message),
          borderRadius: BorderRadius.all(Radius.circular(8.0)),
          clipBehavior: Clip.hardEdge,
        ),
        onPressed: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => ZoomImage(
                      url: ApiClient.baseUrl + message.attachments[0])));
        },
        // padding: EdgeInsets.all(0),
      ),
      margin: logUserMsg
          ? EdgeInsets.only(
              bottom: /*isLastMessageRight(listMessage, id, index) ? 20.0 :*/
                  20.0,
              right: 10.0)
          : EdgeInsets.only(left: 20.0, bottom: 10),
    );
  }

  static Widget widgetShowImages(
      String imageUrl, double imageSize, MessageModel message) {
    return Stack(
      children: [
        CachedNetworkImage(
          imageUrl: imageUrl,
          height: imageSize,
          width: imageSize,
          fit: BoxFit.cover,
          placeholder: (context, url) => Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(),
            ),
          ),
          errorWidget: (context, url, error) => Icon(Icons.error),
        ),
        Positioned(
          bottom: 5,
          right: 5,
          child: Text(
            getTime(message.createdAt),
            style: TextStyle(fontSize: 10, color: colorGrey),
          ),
        )
      ],
    );
  }

/*   static bool isLastMessageLeft(var listMessage, String id, int index) {
    if ((index > 0 &&
            listMessage != null &&
            listMessage[index - 1].get('idFrom') == id) ||
        index == 0) {
      return true;
    } else {
      return false;
    }
  }
 */
  getChatList() {
    widget.socket.emit('view-group-chat', widget.groupId);
    widget.socket.on('view-group-chat', (data) {
      print(data);
      MessagesResponse mResponse = MessagesResponse.fromJson(data);
      if (this.mounted) {
        setState(() {
          listMessage = mResponse.messages;
        });
      }
    });
  }

  sendMessage() {
    DateTime time = DateTime.now();
    var formatter = new DateFormat('dd MMMM yyyy');
    String formattedLocalDate = formatter.format(time);
    String strTime = time.toString();
    String text = textEditingController.text;
    textEditingController.clear();
    print('Message Sent');
    GroupMessageModel message = GroupMessageModel(
        body: text,
        senderId: widget.currentUserId,
        groupId: widget.groupId,
        status: '0',
        messageType: 'txt',
        attachments: [],
        workoutId: '');
    MessageModel message1 = MessageModel(
        body: text,
        senderId: widget.currentUserId,
        sId: '',
        senderName: '',
        senderImage: '',
        messageType: 'txt',
        fileType: '',
        senderEmail: '',
        attachments: [],
        workoutId: '',
        createdAt: strTime,
        updatedAt: strTime,
        formattedLocalDate: formattedLocalDate);
    print('text: ' + message.body);
    print('senderId: ' + message.senderId);
    print('teamId: ' + message.groupId);
    if (this.mounted) {
      setState(() {
        listMessage.insert(0, message1);
      });
    }
    widget.socket.emit('group-message', message);
  }

  sendMediaMessage(List<String> attachments) {
    DateTime time = DateTime.now();
    var formatter = new DateFormat('dd MMMM yyyy');
    String formattedLocalDate = formatter.format(time);
    String strTime = time.toString();
    String text = '';
    print('Message Sent');
    GroupMessageModel message = GroupMessageModel(
        body: text,
        senderId: widget.currentUserId,
        groupId: widget.groupId,
        status: '1',
        messageType: 'img',
        attachments: attachments,
        workoutId: '');
    MessageModel message1 = MessageModel(
        body: text,
        senderId: widget.currentUserId,
        sId: '',
        senderName: '',
        senderImage: '',
        messageType: 'img',
        fileType: '',
        senderEmail: '',
        attachments: attachments,
        workoutId: '',
        createdAt: strTime,
        updatedAt: strTime,
        formattedLocalDate: formattedLocalDate);
    if (this.mounted) {
      setState(() {
        listMessage.insert(0, message1);
      });
    }
    widget.socket.emit('group-message', message);
  }

  uploadImage() async {
    setState(() {
      uploading = true;
    });
    String apiUrl = ApiClient.urlAddChatMedia;
    var request = new http.MultipartRequest("POST", Uri.parse(apiUrl));
    request.files.add(new http.MultipartFile.fromBytes(
        'media', await _image.readAsBytes(),
        filename: path.basename(_image.path)));
    request.send().then((response) {
      setState(() {
        uploading = false;
      });
      if (response.statusCode == 200) {
        getResponse(response);
      } else {
        getError(response);
      }
    }).catchError((error) {
      MySnackBar.showSnackBar(context, 'Error: Check Your Internet Connection');
      print('Error: ' '$error');
    });
  }

  getResponse(var streamedResponse) async {
    var response = await http.Response.fromStream(streamedResponse);
    print(response.body);
    MediaResponse mResponse =
        MediaResponse.fromJson(json.decode(response.body));
    if (mResponse.status) {
      sendMediaMessage(mResponse.result);
    } else {
      setState(() {
        uploading = false;
      });
      MySnackBar.showSnackBar(context, 'Something Went Wrong');
    }
  }

  getError(var streamedResponse) async {
    var response = await http.Response.fromStream(streamedResponse);
    print(response.body);
    MySnackBar.showSnackBar(context, 'Error: Check Your Internet Connection');
  }

  showBottomSheet() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => Container(
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                color: Color(0xFF737373),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.0),
                  topRight: Radius.circular(20.0),
                ),
              ),
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.symmetric(horizontal: 5.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: colorWhite,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20.0),
                    topRight: Radius.circular(20.0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Share',
                      style: TextStyle(
                          color: colorBlack,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    Text('Sharing your workout \'' +
                        widget.workoutName +
                        '\' Here.'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        PrimaryButton(
                          height: 40,
                          width: 100,
                          startColor: colorGrey,
                          endColor: colorGrey,
                          textColor: colorBlack,
                          text: 'Cancel',
                          onPressed: () {
                            Navigator.of(context).pop();
                            cancelShare();
                          },
                        ),
                        PrimaryButton(
                          height: 40,
                          width: 100,
                          text: 'Send',
                          onPressed: () {
                            Navigator.of(context).pop();
                            sendWorkout();
                          },
                        ),
                      ],
                    )
                  ],
                ),
              ),
              height: MediaQuery.of(context).size.height * 0.3,
            ));
  }

  sendWorkout() {
    cancelShare();
    DateTime time = DateTime.now();
    var formatter = new DateFormat('dd MMMM yyyy');
    String formattedLocalDate = formatter.format(time);
    String strTime = time.toString();
    // String text='';
    List<String> image = [];
    image.add(widget.workoutImage);
    print('Message Sent');
    GroupMessageModel message = GroupMessageModel(
        body: widget.workoutName,
        senderId: widget.currentUserId,
        groupId: widget.groupId,
        status: '2',
        messageType: 'workout',
        attachments: image,
        workoutId: widget.workoutId);
    MessageModel message1 = MessageModel(
      body: widget.workoutName,
      senderId: widget.currentUserId,
      sId: '',
      senderName: '',
      senderImage: '',
      messageType: 'workout',
      fileType: '',
      senderEmail: '',
      attachments: image,
      workoutId: widget.workoutId,
      createdAt: strTime,
      updatedAt: strTime,
      formattedLocalDate: formattedLocalDate,
    );
    if (this.mounted) {
      setState(() {
        listMessage.insert(0, message1);
      });
    }
    widget.socket.emit('group-message', message);
  }

  static String getTime(String str) {
    DateTime dateTime = DateTime.parse(str).toLocal();
    return '${dateTime.hour}:${dateTime.minute}';
  }
}
