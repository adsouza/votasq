// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'notification.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AppNotification {

 String get id; String get recipientUid; NotificationPayload get payload; DateTime get createdAt; DateTime get updatedAt; DateTime? get readAt;
/// Create a copy of AppNotification
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppNotificationCopyWith<AppNotification> get copyWith => _$AppNotificationCopyWithImpl<AppNotification>(this as AppNotification, _$identity);

  /// Serializes this AppNotification to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppNotification&&(identical(other.id, id) || other.id == id)&&(identical(other.recipientUid, recipientUid) || other.recipientUid == recipientUid)&&(identical(other.payload, payload) || other.payload == payload)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.readAt, readAt) || other.readAt == readAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,recipientUid,payload,createdAt,updatedAt,readAt);

@override
String toString() {
  return 'AppNotification(id: $id, recipientUid: $recipientUid, payload: $payload, createdAt: $createdAt, updatedAt: $updatedAt, readAt: $readAt)';
}


}

/// @nodoc
abstract mixin class $AppNotificationCopyWith<$Res>  {
  factory $AppNotificationCopyWith(AppNotification value, $Res Function(AppNotification) _then) = _$AppNotificationCopyWithImpl;
@useResult
$Res call({
 String id, String recipientUid, NotificationPayload payload, DateTime createdAt, DateTime updatedAt, DateTime? readAt
});


$NotificationPayloadCopyWith<$Res> get payload;

}
/// @nodoc
class _$AppNotificationCopyWithImpl<$Res>
    implements $AppNotificationCopyWith<$Res> {
  _$AppNotificationCopyWithImpl(this._self, this._then);

  final AppNotification _self;
  final $Res Function(AppNotification) _then;

/// Create a copy of AppNotification
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? recipientUid = null,Object? payload = null,Object? createdAt = null,Object? updatedAt = null,Object? readAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,recipientUid: null == recipientUid ? _self.recipientUid : recipientUid // ignore: cast_nullable_to_non_nullable
as String,payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as NotificationPayload,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,readAt: freezed == readAt ? _self.readAt : readAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of AppNotification
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NotificationPayloadCopyWith<$Res> get payload {
  
  return $NotificationPayloadCopyWith<$Res>(_self.payload, (value) {
    return _then(_self.copyWith(payload: value));
  });
}
}


/// Adds pattern-matching-related methods to [AppNotification].
extension AppNotificationPatterns on AppNotification {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppNotification value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppNotification() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppNotification value)  $default,){
final _that = this;
switch (_that) {
case _AppNotification():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppNotification value)?  $default,){
final _that = this;
switch (_that) {
case _AppNotification() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String recipientUid,  NotificationPayload payload,  DateTime createdAt,  DateTime updatedAt,  DateTime? readAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppNotification() when $default != null:
return $default(_that.id,_that.recipientUid,_that.payload,_that.createdAt,_that.updatedAt,_that.readAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String recipientUid,  NotificationPayload payload,  DateTime createdAt,  DateTime updatedAt,  DateTime? readAt)  $default,) {final _that = this;
switch (_that) {
case _AppNotification():
return $default(_that.id,_that.recipientUid,_that.payload,_that.createdAt,_that.updatedAt,_that.readAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String recipientUid,  NotificationPayload payload,  DateTime createdAt,  DateTime updatedAt,  DateTime? readAt)?  $default,) {final _that = this;
switch (_that) {
case _AppNotification() when $default != null:
return $default(_that.id,_that.recipientUid,_that.payload,_that.createdAt,_that.updatedAt,_that.readAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppNotification implements AppNotification {
  const _AppNotification({required this.id, required this.recipientUid, required this.payload, required this.createdAt, required this.updatedAt, this.readAt});
  factory _AppNotification.fromJson(Map<String, dynamic> json) => _$AppNotificationFromJson(json);

@override final  String id;
@override final  String recipientUid;
@override final  NotificationPayload payload;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? readAt;

/// Create a copy of AppNotification
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppNotificationCopyWith<_AppNotification> get copyWith => __$AppNotificationCopyWithImpl<_AppNotification>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AppNotificationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppNotification&&(identical(other.id, id) || other.id == id)&&(identical(other.recipientUid, recipientUid) || other.recipientUid == recipientUid)&&(identical(other.payload, payload) || other.payload == payload)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.readAt, readAt) || other.readAt == readAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,recipientUid,payload,createdAt,updatedAt,readAt);

@override
String toString() {
  return 'AppNotification(id: $id, recipientUid: $recipientUid, payload: $payload, createdAt: $createdAt, updatedAt: $updatedAt, readAt: $readAt)';
}


}

/// @nodoc
abstract mixin class _$AppNotificationCopyWith<$Res> implements $AppNotificationCopyWith<$Res> {
  factory _$AppNotificationCopyWith(_AppNotification value, $Res Function(_AppNotification) _then) = __$AppNotificationCopyWithImpl;
@override @useResult
$Res call({
 String id, String recipientUid, NotificationPayload payload, DateTime createdAt, DateTime updatedAt, DateTime? readAt
});


@override $NotificationPayloadCopyWith<$Res> get payload;

}
/// @nodoc
class __$AppNotificationCopyWithImpl<$Res>
    implements _$AppNotificationCopyWith<$Res> {
  __$AppNotificationCopyWithImpl(this._self, this._then);

  final _AppNotification _self;
  final $Res Function(_AppNotification) _then;

/// Create a copy of AppNotification
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? recipientUid = null,Object? payload = null,Object? createdAt = null,Object? updatedAt = null,Object? readAt = freezed,}) {
  return _then(_AppNotification(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,recipientUid: null == recipientUid ? _self.recipientUid : recipientUid // ignore: cast_nullable_to_non_nullable
as String,payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as NotificationPayload,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,readAt: freezed == readAt ? _self.readAt : readAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of AppNotification
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NotificationPayloadCopyWith<$Res> get payload {
  
  return $NotificationPayloadCopyWith<$Res>(_self.payload, (value) {
    return _then(_self.copyWith(payload: value));
  });
}
}

NotificationPayload _$NotificationPayloadFromJson(
  Map<String, dynamic> json
) {
        switch (json['type']) {
                  case 'voteReceived':
          return VoteReceivedPayload.fromJson(
            json
          );
                case 'problemForked':
          return ProblemForkedPayload.fromJson(
            json
          );
                case 'problemLinked':
          return ProblemLinkedPayload.fromJson(
            json
          );
                case 'problemRevised':
          return ProblemRevisedPayload.fromJson(
            json
          );
                case 'forkAdopted':
          return ForkAdoptedPayload.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'type',
  'NotificationPayload',
  'Invalid union type "${json['type']}"!'
);
        }
      
}

/// @nodoc
mixin _$NotificationPayload {



  /// Serializes this NotificationPayload to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NotificationPayload);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NotificationPayload()';
}


}

/// @nodoc
class $NotificationPayloadCopyWith<$Res>  {
$NotificationPayloadCopyWith(NotificationPayload _, $Res Function(NotificationPayload) __);
}


/// Adds pattern-matching-related methods to [NotificationPayload].
extension NotificationPayloadPatterns on NotificationPayload {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( VoteReceivedPayload value)?  voteReceived,TResult Function( ProblemForkedPayload value)?  problemForked,TResult Function( ProblemLinkedPayload value)?  problemLinked,TResult Function( ProblemRevisedPayload value)?  problemRevised,TResult Function( ForkAdoptedPayload value)?  forkAdopted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case VoteReceivedPayload() when voteReceived != null:
return voteReceived(_that);case ProblemForkedPayload() when problemForked != null:
return problemForked(_that);case ProblemLinkedPayload() when problemLinked != null:
return problemLinked(_that);case ProblemRevisedPayload() when problemRevised != null:
return problemRevised(_that);case ForkAdoptedPayload() when forkAdopted != null:
return forkAdopted(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( VoteReceivedPayload value)  voteReceived,required TResult Function( ProblemForkedPayload value)  problemForked,required TResult Function( ProblemLinkedPayload value)  problemLinked,required TResult Function( ProblemRevisedPayload value)  problemRevised,required TResult Function( ForkAdoptedPayload value)  forkAdopted,}){
final _that = this;
switch (_that) {
case VoteReceivedPayload():
return voteReceived(_that);case ProblemForkedPayload():
return problemForked(_that);case ProblemLinkedPayload():
return problemLinked(_that);case ProblemRevisedPayload():
return problemRevised(_that);case ForkAdoptedPayload():
return forkAdopted(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( VoteReceivedPayload value)?  voteReceived,TResult? Function( ProblemForkedPayload value)?  problemForked,TResult? Function( ProblemLinkedPayload value)?  problemLinked,TResult? Function( ProblemRevisedPayload value)?  problemRevised,TResult? Function( ForkAdoptedPayload value)?  forkAdopted,}){
final _that = this;
switch (_that) {
case VoteReceivedPayload() when voteReceived != null:
return voteReceived(_that);case ProblemForkedPayload() when problemForked != null:
return problemForked(_that);case ProblemLinkedPayload() when problemLinked != null:
return problemLinked(_that);case ProblemRevisedPayload() when problemRevised != null:
return problemRevised(_that);case ForkAdoptedPayload() when forkAdopted != null:
return forkAdopted(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String problemId,  String actorUid)?  voteReceived,TResult Function( String originalProblemId,  String forkProblemId,  String actorUid)?  problemForked,TResult Function( String linkedProblemId,  String linkerProblemId,  String actorUid)?  problemLinked,TResult Function( String problemId,  int newVersion)?  problemRevised,TResult Function( String forkProblemId,  String originalProblemId,  int newVersion)?  forkAdopted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case VoteReceivedPayload() when voteReceived != null:
return voteReceived(_that.problemId,_that.actorUid);case ProblemForkedPayload() when problemForked != null:
return problemForked(_that.originalProblemId,_that.forkProblemId,_that.actorUid);case ProblemLinkedPayload() when problemLinked != null:
return problemLinked(_that.linkedProblemId,_that.linkerProblemId,_that.actorUid);case ProblemRevisedPayload() when problemRevised != null:
return problemRevised(_that.problemId,_that.newVersion);case ForkAdoptedPayload() when forkAdopted != null:
return forkAdopted(_that.forkProblemId,_that.originalProblemId,_that.newVersion);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String problemId,  String actorUid)  voteReceived,required TResult Function( String originalProblemId,  String forkProblemId,  String actorUid)  problemForked,required TResult Function( String linkedProblemId,  String linkerProblemId,  String actorUid)  problemLinked,required TResult Function( String problemId,  int newVersion)  problemRevised,required TResult Function( String forkProblemId,  String originalProblemId,  int newVersion)  forkAdopted,}) {final _that = this;
switch (_that) {
case VoteReceivedPayload():
return voteReceived(_that.problemId,_that.actorUid);case ProblemForkedPayload():
return problemForked(_that.originalProblemId,_that.forkProblemId,_that.actorUid);case ProblemLinkedPayload():
return problemLinked(_that.linkedProblemId,_that.linkerProblemId,_that.actorUid);case ProblemRevisedPayload():
return problemRevised(_that.problemId,_that.newVersion);case ForkAdoptedPayload():
return forkAdopted(_that.forkProblemId,_that.originalProblemId,_that.newVersion);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String problemId,  String actorUid)?  voteReceived,TResult? Function( String originalProblemId,  String forkProblemId,  String actorUid)?  problemForked,TResult? Function( String linkedProblemId,  String linkerProblemId,  String actorUid)?  problemLinked,TResult? Function( String problemId,  int newVersion)?  problemRevised,TResult? Function( String forkProblemId,  String originalProblemId,  int newVersion)?  forkAdopted,}) {final _that = this;
switch (_that) {
case VoteReceivedPayload() when voteReceived != null:
return voteReceived(_that.problemId,_that.actorUid);case ProblemForkedPayload() when problemForked != null:
return problemForked(_that.originalProblemId,_that.forkProblemId,_that.actorUid);case ProblemLinkedPayload() when problemLinked != null:
return problemLinked(_that.linkedProblemId,_that.linkerProblemId,_that.actorUid);case ProblemRevisedPayload() when problemRevised != null:
return problemRevised(_that.problemId,_that.newVersion);case ForkAdoptedPayload() when forkAdopted != null:
return forkAdopted(_that.forkProblemId,_that.originalProblemId,_that.newVersion);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class VoteReceivedPayload implements NotificationPayload {
  const VoteReceivedPayload({required this.problemId, required this.actorUid, final  String? $type}): $type = $type ?? 'voteReceived';
  factory VoteReceivedPayload.fromJson(Map<String, dynamic> json) => _$VoteReceivedPayloadFromJson(json);

 final  String problemId;
 final  String actorUid;

@JsonKey(name: 'type')
final String $type;


/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VoteReceivedPayloadCopyWith<VoteReceivedPayload> get copyWith => _$VoteReceivedPayloadCopyWithImpl<VoteReceivedPayload>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$VoteReceivedPayloadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VoteReceivedPayload&&(identical(other.problemId, problemId) || other.problemId == problemId)&&(identical(other.actorUid, actorUid) || other.actorUid == actorUid));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,problemId,actorUid);

@override
String toString() {
  return 'NotificationPayload.voteReceived(problemId: $problemId, actorUid: $actorUid)';
}


}

/// @nodoc
abstract mixin class $VoteReceivedPayloadCopyWith<$Res> implements $NotificationPayloadCopyWith<$Res> {
  factory $VoteReceivedPayloadCopyWith(VoteReceivedPayload value, $Res Function(VoteReceivedPayload) _then) = _$VoteReceivedPayloadCopyWithImpl;
@useResult
$Res call({
 String problemId, String actorUid
});




}
/// @nodoc
class _$VoteReceivedPayloadCopyWithImpl<$Res>
    implements $VoteReceivedPayloadCopyWith<$Res> {
  _$VoteReceivedPayloadCopyWithImpl(this._self, this._then);

  final VoteReceivedPayload _self;
  final $Res Function(VoteReceivedPayload) _then;

/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? problemId = null,Object? actorUid = null,}) {
  return _then(VoteReceivedPayload(
problemId: null == problemId ? _self.problemId : problemId // ignore: cast_nullable_to_non_nullable
as String,actorUid: null == actorUid ? _self.actorUid : actorUid // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class ProblemForkedPayload implements NotificationPayload {
  const ProblemForkedPayload({required this.originalProblemId, required this.forkProblemId, required this.actorUid, final  String? $type}): $type = $type ?? 'problemForked';
  factory ProblemForkedPayload.fromJson(Map<String, dynamic> json) => _$ProblemForkedPayloadFromJson(json);

 final  String originalProblemId;
 final  String forkProblemId;
 final  String actorUid;

@JsonKey(name: 'type')
final String $type;


/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProblemForkedPayloadCopyWith<ProblemForkedPayload> get copyWith => _$ProblemForkedPayloadCopyWithImpl<ProblemForkedPayload>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProblemForkedPayloadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProblemForkedPayload&&(identical(other.originalProblemId, originalProblemId) || other.originalProblemId == originalProblemId)&&(identical(other.forkProblemId, forkProblemId) || other.forkProblemId == forkProblemId)&&(identical(other.actorUid, actorUid) || other.actorUid == actorUid));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,originalProblemId,forkProblemId,actorUid);

@override
String toString() {
  return 'NotificationPayload.problemForked(originalProblemId: $originalProblemId, forkProblemId: $forkProblemId, actorUid: $actorUid)';
}


}

/// @nodoc
abstract mixin class $ProblemForkedPayloadCopyWith<$Res> implements $NotificationPayloadCopyWith<$Res> {
  factory $ProblemForkedPayloadCopyWith(ProblemForkedPayload value, $Res Function(ProblemForkedPayload) _then) = _$ProblemForkedPayloadCopyWithImpl;
@useResult
$Res call({
 String originalProblemId, String forkProblemId, String actorUid
});




}
/// @nodoc
class _$ProblemForkedPayloadCopyWithImpl<$Res>
    implements $ProblemForkedPayloadCopyWith<$Res> {
  _$ProblemForkedPayloadCopyWithImpl(this._self, this._then);

  final ProblemForkedPayload _self;
  final $Res Function(ProblemForkedPayload) _then;

/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? originalProblemId = null,Object? forkProblemId = null,Object? actorUid = null,}) {
  return _then(ProblemForkedPayload(
originalProblemId: null == originalProblemId ? _self.originalProblemId : originalProblemId // ignore: cast_nullable_to_non_nullable
as String,forkProblemId: null == forkProblemId ? _self.forkProblemId : forkProblemId // ignore: cast_nullable_to_non_nullable
as String,actorUid: null == actorUid ? _self.actorUid : actorUid // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class ProblemLinkedPayload implements NotificationPayload {
  const ProblemLinkedPayload({required this.linkedProblemId, required this.linkerProblemId, required this.actorUid, final  String? $type}): $type = $type ?? 'problemLinked';
  factory ProblemLinkedPayload.fromJson(Map<String, dynamic> json) => _$ProblemLinkedPayloadFromJson(json);

 final  String linkedProblemId;
 final  String linkerProblemId;
 final  String actorUid;

@JsonKey(name: 'type')
final String $type;


/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProblemLinkedPayloadCopyWith<ProblemLinkedPayload> get copyWith => _$ProblemLinkedPayloadCopyWithImpl<ProblemLinkedPayload>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProblemLinkedPayloadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProblemLinkedPayload&&(identical(other.linkedProblemId, linkedProblemId) || other.linkedProblemId == linkedProblemId)&&(identical(other.linkerProblemId, linkerProblemId) || other.linkerProblemId == linkerProblemId)&&(identical(other.actorUid, actorUid) || other.actorUid == actorUid));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,linkedProblemId,linkerProblemId,actorUid);

@override
String toString() {
  return 'NotificationPayload.problemLinked(linkedProblemId: $linkedProblemId, linkerProblemId: $linkerProblemId, actorUid: $actorUid)';
}


}

/// @nodoc
abstract mixin class $ProblemLinkedPayloadCopyWith<$Res> implements $NotificationPayloadCopyWith<$Res> {
  factory $ProblemLinkedPayloadCopyWith(ProblemLinkedPayload value, $Res Function(ProblemLinkedPayload) _then) = _$ProblemLinkedPayloadCopyWithImpl;
@useResult
$Res call({
 String linkedProblemId, String linkerProblemId, String actorUid
});




}
/// @nodoc
class _$ProblemLinkedPayloadCopyWithImpl<$Res>
    implements $ProblemLinkedPayloadCopyWith<$Res> {
  _$ProblemLinkedPayloadCopyWithImpl(this._self, this._then);

  final ProblemLinkedPayload _self;
  final $Res Function(ProblemLinkedPayload) _then;

/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? linkedProblemId = null,Object? linkerProblemId = null,Object? actorUid = null,}) {
  return _then(ProblemLinkedPayload(
linkedProblemId: null == linkedProblemId ? _self.linkedProblemId : linkedProblemId // ignore: cast_nullable_to_non_nullable
as String,linkerProblemId: null == linkerProblemId ? _self.linkerProblemId : linkerProblemId // ignore: cast_nullable_to_non_nullable
as String,actorUid: null == actorUid ? _self.actorUid : actorUid // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class ProblemRevisedPayload implements NotificationPayload {
  const ProblemRevisedPayload({required this.problemId, required this.newVersion, final  String? $type}): $type = $type ?? 'problemRevised';
  factory ProblemRevisedPayload.fromJson(Map<String, dynamic> json) => _$ProblemRevisedPayloadFromJson(json);

 final  String problemId;
 final  int newVersion;

@JsonKey(name: 'type')
final String $type;


/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProblemRevisedPayloadCopyWith<ProblemRevisedPayload> get copyWith => _$ProblemRevisedPayloadCopyWithImpl<ProblemRevisedPayload>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProblemRevisedPayloadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProblemRevisedPayload&&(identical(other.problemId, problemId) || other.problemId == problemId)&&(identical(other.newVersion, newVersion) || other.newVersion == newVersion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,problemId,newVersion);

@override
String toString() {
  return 'NotificationPayload.problemRevised(problemId: $problemId, newVersion: $newVersion)';
}


}

/// @nodoc
abstract mixin class $ProblemRevisedPayloadCopyWith<$Res> implements $NotificationPayloadCopyWith<$Res> {
  factory $ProblemRevisedPayloadCopyWith(ProblemRevisedPayload value, $Res Function(ProblemRevisedPayload) _then) = _$ProblemRevisedPayloadCopyWithImpl;
@useResult
$Res call({
 String problemId, int newVersion
});




}
/// @nodoc
class _$ProblemRevisedPayloadCopyWithImpl<$Res>
    implements $ProblemRevisedPayloadCopyWith<$Res> {
  _$ProblemRevisedPayloadCopyWithImpl(this._self, this._then);

  final ProblemRevisedPayload _self;
  final $Res Function(ProblemRevisedPayload) _then;

/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? problemId = null,Object? newVersion = null,}) {
  return _then(ProblemRevisedPayload(
problemId: null == problemId ? _self.problemId : problemId // ignore: cast_nullable_to_non_nullable
as String,newVersion: null == newVersion ? _self.newVersion : newVersion // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
@JsonSerializable()

class ForkAdoptedPayload implements NotificationPayload {
  const ForkAdoptedPayload({required this.forkProblemId, required this.originalProblemId, required this.newVersion, final  String? $type}): $type = $type ?? 'forkAdopted';
  factory ForkAdoptedPayload.fromJson(Map<String, dynamic> json) => _$ForkAdoptedPayloadFromJson(json);

 final  String forkProblemId;
 final  String originalProblemId;
 final  int newVersion;

@JsonKey(name: 'type')
final String $type;


/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ForkAdoptedPayloadCopyWith<ForkAdoptedPayload> get copyWith => _$ForkAdoptedPayloadCopyWithImpl<ForkAdoptedPayload>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ForkAdoptedPayloadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ForkAdoptedPayload&&(identical(other.forkProblemId, forkProblemId) || other.forkProblemId == forkProblemId)&&(identical(other.originalProblemId, originalProblemId) || other.originalProblemId == originalProblemId)&&(identical(other.newVersion, newVersion) || other.newVersion == newVersion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,forkProblemId,originalProblemId,newVersion);

@override
String toString() {
  return 'NotificationPayload.forkAdopted(forkProblemId: $forkProblemId, originalProblemId: $originalProblemId, newVersion: $newVersion)';
}


}

/// @nodoc
abstract mixin class $ForkAdoptedPayloadCopyWith<$Res> implements $NotificationPayloadCopyWith<$Res> {
  factory $ForkAdoptedPayloadCopyWith(ForkAdoptedPayload value, $Res Function(ForkAdoptedPayload) _then) = _$ForkAdoptedPayloadCopyWithImpl;
@useResult
$Res call({
 String forkProblemId, String originalProblemId, int newVersion
});




}
/// @nodoc
class _$ForkAdoptedPayloadCopyWithImpl<$Res>
    implements $ForkAdoptedPayloadCopyWith<$Res> {
  _$ForkAdoptedPayloadCopyWithImpl(this._self, this._then);

  final ForkAdoptedPayload _self;
  final $Res Function(ForkAdoptedPayload) _then;

/// Create a copy of NotificationPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? forkProblemId = null,Object? originalProblemId = null,Object? newVersion = null,}) {
  return _then(ForkAdoptedPayload(
forkProblemId: null == forkProblemId ? _self.forkProblemId : forkProblemId // ignore: cast_nullable_to_non_nullable
as String,originalProblemId: null == originalProblemId ? _self.originalProblemId : originalProblemId // ignore: cast_nullable_to_non_nullable
as String,newVersion: null == newVersion ? _self.newVersion : newVersion // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
