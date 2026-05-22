// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'problem_link.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ProblemLink {

 String get targetId; ProblemLinkKind get kind;
/// Create a copy of ProblemLink
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProblemLinkCopyWith<ProblemLink> get copyWith => _$ProblemLinkCopyWithImpl<ProblemLink>(this as ProblemLink, _$identity);

  /// Serializes this ProblemLink to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProblemLink&&(identical(other.targetId, targetId) || other.targetId == targetId)&&(identical(other.kind, kind) || other.kind == kind));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,targetId,kind);

@override
String toString() {
  return 'ProblemLink(targetId: $targetId, kind: $kind)';
}


}

/// @nodoc
abstract mixin class $ProblemLinkCopyWith<$Res>  {
  factory $ProblemLinkCopyWith(ProblemLink value, $Res Function(ProblemLink) _then) = _$ProblemLinkCopyWithImpl;
@useResult
$Res call({
 String targetId, ProblemLinkKind kind
});




}
/// @nodoc
class _$ProblemLinkCopyWithImpl<$Res>
    implements $ProblemLinkCopyWith<$Res> {
  _$ProblemLinkCopyWithImpl(this._self, this._then);

  final ProblemLink _self;
  final $Res Function(ProblemLink) _then;

/// Create a copy of ProblemLink
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? targetId = null,Object? kind = null,}) {
  return _then(_self.copyWith(
targetId: null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ProblemLinkKind,
  ));
}

}


/// Adds pattern-matching-related methods to [ProblemLink].
extension ProblemLinkPatterns on ProblemLink {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProblemLink value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProblemLink() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProblemLink value)  $default,){
final _that = this;
switch (_that) {
case _ProblemLink():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProblemLink value)?  $default,){
final _that = this;
switch (_that) {
case _ProblemLink() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String targetId,  ProblemLinkKind kind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProblemLink() when $default != null:
return $default(_that.targetId,_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String targetId,  ProblemLinkKind kind)  $default,) {final _that = this;
switch (_that) {
case _ProblemLink():
return $default(_that.targetId,_that.kind);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String targetId,  ProblemLinkKind kind)?  $default,) {final _that = this;
switch (_that) {
case _ProblemLink() when $default != null:
return $default(_that.targetId,_that.kind);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProblemLink implements ProblemLink {
  const _ProblemLink({required this.targetId, required this.kind});
  factory _ProblemLink.fromJson(Map<String, dynamic> json) => _$ProblemLinkFromJson(json);

@override final  String targetId;
@override final  ProblemLinkKind kind;

/// Create a copy of ProblemLink
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProblemLinkCopyWith<_ProblemLink> get copyWith => __$ProblemLinkCopyWithImpl<_ProblemLink>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProblemLinkToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProblemLink&&(identical(other.targetId, targetId) || other.targetId == targetId)&&(identical(other.kind, kind) || other.kind == kind));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,targetId,kind);

@override
String toString() {
  return 'ProblemLink(targetId: $targetId, kind: $kind)';
}


}

/// @nodoc
abstract mixin class _$ProblemLinkCopyWith<$Res> implements $ProblemLinkCopyWith<$Res> {
  factory _$ProblemLinkCopyWith(_ProblemLink value, $Res Function(_ProblemLink) _then) = __$ProblemLinkCopyWithImpl;
@override @useResult
$Res call({
 String targetId, ProblemLinkKind kind
});




}
/// @nodoc
class __$ProblemLinkCopyWithImpl<$Res>
    implements _$ProblemLinkCopyWith<$Res> {
  __$ProblemLinkCopyWithImpl(this._self, this._then);

  final _ProblemLink _self;
  final $Res Function(_ProblemLink) _then;

/// Create a copy of ProblemLink
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? targetId = null,Object? kind = null,}) {
  return _then(_ProblemLink(
targetId: null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ProblemLinkKind,
  ));
}


}

// dart format on
