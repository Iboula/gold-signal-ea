FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY GoldSignal.Dashboard.csproj ./
RUN dotnet restore GoldSignal.Dashboard.csproj

COPY . ./
RUN dotnet publish GoldSignal.Dashboard.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM runtime AS final
WORKDIR /app
COPY --from=build /app/publish ./

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "GoldSignal.Dashboard.dll"]
