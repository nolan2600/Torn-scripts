package com.torn.bountyhunter.api

import com.torn.bountyhunter.data.BountiesResponse
import com.torn.bountyhunter.data.RankedWarsResponse
import com.torn.bountyhunter.data.UserProfileResponse
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Url

interface TornApiService {

    @GET("v2/torn/bounties")
    suspend fun getBounties(
        @Query("key") key: String,
        @Query("limit") limit: Int = 100,
        @Query("offset") offset: Int = 0
    ): BountiesResponse

    /** Used for paginated next-page URLs which already contain all params. */
    @GET
    suspend fun getBountiesByUrl(@Url url: String): BountiesResponse

    @GET("v2/user/{id}/profile")
    suspend fun getUserProfile(
        @Path("id") userId: Int,
        @Query("key") key: String
    ): UserProfileResponse

    @GET("v2/user/profile")
    suspend fun getMyProfile(@Query("key") key: String): UserProfileResponse

    /** Clean v2 endpoint — avoids manual URL construction. */
    @GET("v2/torn")
    suspend fun getWarFactions(
        @Query("key") key: String,
        @Query(value = "selections", encoded = true) selections: String = "rankedwars,territorywars"
    ): RankedWarsResponse
}
