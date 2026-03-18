// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'problem.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Problem {

 String get id; String get description; int get votes; bool get solved; DateTime? get createdAt; DateTime? get lastUpdatedAt;
/// Create a copy of Problem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProblemCopyWith<Problem> get copyWith => _$ProblemCopyWithImpl<Problem>(this as Problem, _$identity);

  /// Serializes this Problem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Problem&&(identical(other.id, id) || other.id == id)&&(identical(other.description, description) || other.description == description)&&(identical(other.votes, votes) || other.votes == votes)&&(identical(other.solved, solved) || other.solved == solved)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.lastUpdatedAt, lastUpdatedAt) || other.lastUpdatedAt == lastUpdatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,description,votes,solved,createdAt,lastUpdatedAt);

@override
String toString() {
  return 'Problem(id: $id, description: $description, votes: $votes, solved: $solved, createdAt: $createdAt, lastUpdatedAt: $lastUpdatedAt)';
}


}

/// @nodoc
abstract mixin class $ProblemCopyWith<$Res>  {
  factory $ProblemCopyWith(Problem value, $Res Function(Problem) _then) = _$ProblemCopyWithImpl;
@useResult
$Res call({
 String id, String description, int votes, bool solved, DateTime? createdAt, DateTime? lastUpdatedAt
});




}
/// @nodoc
class _$ProblemCopyWithImpl<$Res>
    implements $ProblemCopyWith<$Res> {
  _$ProblemCopyWithImpl(this._self, this._then);

  final Problem _self;
  final $Res Function(Problem) _then;

/// Create a copy of Problem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? description = null,Object? votes = null,Object? solved = null,Object? createdAt = freezed,Object? lastUpdatedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,votes: null == votes ? _self.votes : votes // ignore: cast_nullable_to_non_nullable
as int,solved: null == solved ? _self.solved : solved // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastUpdatedAt: freezed == lastUpdatedAt ? _self.lastUpdatedAt : lastUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Problem].
extension ProblemPatterns on Problem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Problem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Problem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Problem value)  $default,){
final _that = this;
switch (_that) {
case _Problem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Problem value)?  $default,){
final _that = this;
switch (_that) {
case _Problem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String description,  int votes,  bool solved,  DateTime? createdAt,  DateTime? lastUpdatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Problem() when $default != null:
return $default(_that.id,_that.description,_that.votes,_that.solved,_that.createdAt,_that.lastUpdatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String description,  int votes,  bool solved,  DateTime? createdAt,  DateTime? lastUpdatedAt)  $default,) {final _that = this;
switch (_that) {
case _Problem():
return $default(_that.id,_that.description,_that.votes,_that.solved,_that.createdAt,_that.lastUpdatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String description,  int votes,  bool solved,  DateTime? createdAt,  DateTime? lastUpdatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Problem() when $default != null:
return $default(_that.id,_that.description,_that.votes,_that.solved,_that.createdAt,_that.lastUpdatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Problem implements Problem {
  const _Problem({required this.id, required this.description, this.votes = 1, this.solved = false, this.createdAt, this.lastUpdatedAt});
  factory _Problem.fromJson(Map<String, dynamic> json) => _$ProblemFromJson(json);

@override final  String id;
@override final  String description;
@override@JsonKey() final  int votes;
@override@JsonKey() final  bool solved;
@override final  DateTime? createdAt;
@override final  DateTime? lastUpdatedAt;

/// Create a copy of Problem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProblemCopyWith<_Problem> get copyWith => __$ProblemCopyWithImpl<_Problem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProblemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Problem&&(identical(other.id, id) || other.id == id)&&(identical(other.description, description) || other.description == description)&&(identical(other.votes, votes) || other.votes == votes)&&(identical(other.solved, solved) || other.solved == solved)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.lastUpdatedAt, lastUpdatedAt) || other.lastUpdatedAt == lastUpdatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,description,votes,solved,createdAt,lastUpdatedAt);

@override
String toString() {
  return 'Problem(id: $id, description: $description, votes: $votes, solved: $solved, createdAt: $createdAt, lastUpdatedAt: $lastUpdatedAt)';
}


}

/// @nodoc
abstract mixin class _$ProblemCopyWith<$Res> implements $ProblemCopyWith<$Res> {
  factory _$ProblemCopyWith(_Problem value, $Res Function(_Problem) _then) = __$ProblemCopyWithImpl;
@override @useResult
$Res call({
 String id, String description, int votes, bool solved, DateTime? createdAt, DateTime? lastUpdatedAt
});




}
/// @nodoc
class __$ProblemCopyWithImpl<$Res>
    implements _$ProblemCopyWith<$Res> {
  __$ProblemCopyWithImpl(this._self, this._then);

  final _Problem _self;
  final $Res Function(_Problem) _then;

/// Create a copy of Problem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? description = null,Object? votes = null,Object? solved = null,Object? createdAt = freezed,Object? lastUpdatedAt = freezed,}) {
  return _then(_Problem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,votes: null == votes ? _self.votes : votes // ignore: cast_nullable_to_non_nullable
as int,solved: null == solved ? _self.solved : solved // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastUpdatedAt: freezed == lastUpdatedAt ? _self.lastUpdatedAt : lastUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
