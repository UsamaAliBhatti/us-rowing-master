import 'package:us_rowing/models/LikeModel.dart';

class LikesResponse {
  late bool status;
  late String message;
  late List<LikeModel> post;

  LikesResponse({required this.status, required this.message, required this.post});

  LikesResponse.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    message = json['message'];
    if (json['post'] != null) {
      post = [];
      json['post'].forEach((v) {
        post.add(new LikeModel.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['status'] = this.status;
    data['message'] = this.message;
    data['post'] = this.post.map((v) => v.toJson()).toList();
    return data;
  }
}