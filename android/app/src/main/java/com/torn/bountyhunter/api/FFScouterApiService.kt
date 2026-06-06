package com.torn.bountyhunter.api

import com.torn.bountyhunter.data.FFScouterEntry
import com.torn.bountyhunter.data.FFScouterKeyCheckResponse
import retrofit2.http.GET
import retrofit2.http.Query

interface FFScouterApiService {

    @GET("v1/get-stats")
    suspend fun getStats(
        @Query("key") key: String,
        @Query("targets") targets: String
    ): List<FFScouterEntry>

    @GET("v1/check-key")
    suspend fun checkKey(@Query("key") key: String): FFScouterKeyCheckResponse
}
