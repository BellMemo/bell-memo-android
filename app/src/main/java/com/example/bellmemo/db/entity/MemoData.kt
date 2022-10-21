package com.example.bellmemo.db.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.UUID

@Entity
data class MemoData(
    @PrimaryKey val id:UUID,
    @ColumnInfo(name = "title") val title: String?,
    @ColumnInfo(name = "content") val content: String?,
    @ColumnInfo(name = "created") val created: Int?,
    @ColumnInfo(name = "updated") val updated: Int?
)
