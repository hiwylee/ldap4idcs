import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import Head from 'next/head';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { useForm } from 'react-hook-form';
import toast from 'react-hot-toast';
import {
  EyeIcon,
  EyeSlashIcon,
  ArrowRightIcon,
  ShieldCheckIcon,
  CloudIcon,
  UsersIcon,
  LockClosedIcon
} from '@heroicons/react/24/outline';

import { useAuth } from '../hooks/useAuth';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { Card } from '../components/ui/Card';

interface LoginFormData {
  username: string;
  password: string;
  rememberMe: boolean;
}

const LoginPage: React.FC = () => {
  const router = useRouter();
  const { login, loginWithIDCS, isLoading, isAuthenticated } = useAuth();
  const [showPassword, setShowPassword] = useState(false);
  const [loginMethod, setLoginMethod] = useState<'idcs' | 'ldap'>('idcs');

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
    reset
  } = useForm<LoginFormData>();

  // Redirect if already authenticated
  useEffect(() => {
    if (isAuthenticated) {
      const redirectTo = (router.query.redirect as string) || '/dashboard';
      router.push(redirectTo);
    }
  }, [isAuthenticated, router]);

  // Handle IDCS SSO login
  const handleIDCSLogin = async () => {
    try {
      await loginWithIDCS();
    } catch (error) {
      toast.error('IDCS 로그인에 실패했습니다.');
      console.error('IDCS login error:', error);
    }
  };

  // Handle LDAP direct login
  const handleLDAPLogin = async (data: LoginFormData) => {
    try {
      await login(data.username, data.password, data.rememberMe);
      const redirectTo = (router.query.redirect as string) || '/dashboard';
      router.push(redirectTo);
      toast.success('로그인에 성공했습니다.');
    } catch (error: any) {
      toast.error(error.message || '로그인에 실패했습니다.');
      reset({ password: '' });
    }
  };

  const features = [
    {
      icon: CloudIcon,
      title: 'OCI IDCS 통합',
      description: 'Oracle Cloud Infrastructure Identity Cloud Service와 완전 통합'
    },
    {
      icon: ShieldCheckIcon,
      title: '보안 인증',
      description: 'SAML 2.0 및 OAuth 2.0 표준 기반 보안 인증'
    },
    {
      icon: UsersIcon,
      title: 'Single Sign-On',
      description: '하나의 로그인으로 모든 애플리케이션 접근'
    }
  ];

  return (
    <>
      <Head>
        <title>로그인 - OCI IDCS SSO 플랫폼</title>
        <meta name="description" content="OCI IDCS 통합 SSO 플랫폼에 로그인하세요" />
      </Head>

      <div className="min-h-screen bg-gradient-to-br from-blue-50 via-white to-indigo-50">
        {/* Background Pattern */}
        <div className="absolute inset-0 bg-[url('/grid.svg')] bg-center [mask-image:linear-gradient(180deg,white,rgba(255,255,255,0))]" />
        
        <div className="relative flex min-h-screen">
          {/* Left Side - Features */}
          <div className="hidden lg:flex lg:w-1/2 lg:flex-col lg:justify-center lg:px-12 xl:px-16">
            <motion.div
              initial={{ opacity: 0, x: -50 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.8 }}
              className="max-w-md"
            >
              <div className="mb-8">
                <div className="flex items-center space-x-3">
                  <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-r from-blue-600 to-indigo-600">
                    <LockClosedIcon className="h-6 w-6 text-white" />
                  </div>
                  <div>
                    <h1 className="text-2xl font-bold text-gray-900">
                      SSO Platform
                    </h1>
                    <p className="text-sm text-gray-600">OCI IDCS 통합</p>
                  </div>
                </div>
              </div>

              <h2 className="text-3xl font-bold text-gray-900 mb-6">
                통합 인증 플랫폼에
                <br />
                <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-600 to-indigo-600">
                  오신 것을 환영합니다
                </span>
              </h2>

              <p className="text-lg text-gray-600 mb-8">
                Oracle Cloud Infrastructure Identity Cloud Service와 
                OpenLDAP을 연동한 통합 SSO 솔루션으로 안전하고 
                편리한 인증 경험을 제공합니다.
              </p>

              <div className="space-y-6">
                {features.map((feature, index) => (
                  <motion.div
                    key={feature.title}
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.6, delay: 0.2 + index * 0.1 }}
                    className="flex items-start space-x-4"
                  >
                    <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-100">
                      <feature.icon className="h-5 w-5 text-blue-600" />
                    </div>
                    <div>
                      <h3 className="font-semibold text-gray-900">
                        {feature.title}
                      </h3>
                      <p className="text-sm text-gray-600">
                        {feature.description}
                      </p>
                    </div>
                  </motion.div>
                ))}
              </div>
            </motion.div>
          </div>

          {/* Right Side - Login Form */}
          <div className="flex w-full flex-col justify-center px-6 py-12 lg:w-1/2 lg:px-8">
            <motion.div
              initial={{ opacity: 0, y: 50 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.2 }}
              className="mx-auto w-full max-w-md"
            >
              {/* Mobile Logo */}
              <div className="mb-8 flex justify-center lg:hidden">
                <div className="flex items-center space-x-3">
                  <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-r from-blue-600 to-indigo-600">
                    <LockClosedIcon className="h-6 w-6 text-white" />
                  </div>
                  <div>
                    <h1 className="text-xl font-bold text-gray-900">
                      SSO Platform
                    </h1>
                    <p className="text-xs text-gray-600">OCI IDCS 통합</p>
                  </div>
                </div>
              </div>

              <Card className="p-8">
                <div className="mb-6">
                  <h2 className="text-2xl font-bold text-gray-900">로그인</h2>
                  <p className="mt-2 text-sm text-gray-600">
                    계정에 로그인하여 시작하세요
                  </p>
                </div>

                {/* Login Method Toggle */}
                <div className="mb-6">
                  <div className="flex rounded-lg bg-gray-100 p-1">
                    <button
                      type="button"
                      onClick={() => setLoginMethod('idcs')}
                      className="w-full text-center text-sm text-blue-600 hover:text-blue-500"
                    >
                      IDCS SSO 사용하기
                    </button>
                  </form>
                )}

                {/* Footer */}
                <div className="mt-8 text-center">
                  <p className="text-xs text-gray-500">
                    계속 진행하면{' '}
                    <Link href="/terms" className="text-blue-600 hover:underline">
                      이용약관
                    </Link>
                    {' '}및{' '}
                    <Link href="/privacy" className="text-blue-600 hover:underline">
                      개인정보처리방침
                    </Link>
                    에 동의하는 것으로 간주됩니다.
                  </p>
                </div>
              </Card>

              {/* Help Links */}
              <div className="mt-6 text-center space-y-2">
                <p className="text-sm text-gray-600">
                  로그인에 문제가 있으신가요?{' '}
                  <Link href="/support" className="text-blue-600 hover:underline">
                    고객지원 센터
                  </Link>
                </p>
                <p className="text-xs text-gray-500">
                  버전 1.0.0 | © 2024 Company. All rights reserved.
                </p>
              </div>
            </motion.div>
          </div>
        </div>
      </div>
    </>
  );
};

export default LoginPage; setLoginMethod('idcs')}
                      className={`flex-1 rounded-md px-3 py-2 text-sm font-medium transition-all ${
                        loginMethod === 'idcs'
                          ? 'bg-white text-blue-600 shadow-sm'
                          : 'text-gray-600 hover:text-gray-900'
                      }`}
                    >
                      IDCS SSO
                    </button>
                    <button
                      type="button"
                      onClick={() => setLoginMethod('ldap')}
                      className={`flex-1 rounded-md px-3 py-2 text-sm font-medium transition-all ${
                        loginMethod === 'ldap'
                          ? 'bg-white text-blue-600 shadow-sm'
                          : 'text-gray-600 hover:text-gray-900'
                      }`}
                    >
                      직접 로그인
                    </button>
                  </div>
                </div>

                {loginMethod === 'idcs' ? (
                  /* IDCS SSO Login */
                  <div className="space-y-4">
                    <Button
                      onClick={handleIDCSLogin}
                      disabled={isLoading}
                      className="w-full bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700"
                      size="lg"
                    >
                      {isLoading ? (
                        <LoadingSpinner size="sm" className="mr-2" />
                      ) : (
                        <CloudIcon className="mr-2 h-5 w-5" />
                      )}
                      IDCS로 로그인
                    </Button>

                    <div className="relative">
                      <div className="absolute inset-0 flex items-center">
                        <div className="w-full border-t border-gray-300" />
                      </div>
                      <div className="relative flex justify-center text-sm">
                        <span className="bg-white px-2 text-gray-500">
                          또는 계정이 있다면
                        </span>
                      </div>
                    </div>

                    <button
                      type="button"
                      onClick={() => setLoginMethod('ldap')}
                      className="w-full text-center text-sm text-blue-600 hover:text-blue-500"
                    >
                      직접 로그인 사용하기
                    </button>
                  </div>
                ) : (
                  /* LDAP Direct Login */
                  <form onSubmit={handleSubmit(handleLDAPLogin)} className="space-y-4">
                    <div>
                      <label htmlFor="username" className="block text-sm font-medium text-gray-700">
                        사용자명
                      </label>
                      <Input
                        id="username"
                        type="text"
                        autoComplete="username"
                        placeholder="사용자명을 입력하세요"
                        {...register('username', {
                          required: '사용자명을 입력해주세요',
                          minLength: {
                            value: 2,
                            message: '사용자명은 최소 2자 이상이어야 합니다'
                          }
                        })}
                        error={errors.username?.message}
                        className="mt-1"
                      />
                    </div>

                    <div>
                      <label htmlFor="password" className="block text-sm font-medium text-gray-700">
                        비밀번호
                      </label>
                      <div className="relative mt-1">
                        <Input
                          id="password"
                          type={showPassword ? 'text' : 'password'}
                          autoComplete="current-password"
                          placeholder="비밀번호를 입력하세요"
                          {...register('password', {
                            required: '비밀번호를 입력해주세요',
                            minLength: {
                              value: 6,
                              message: '비밀번호는 최소 6자 이상이어야 합니다'
                            }
                          })}
                          error={errors.password?.message}
                          className="pr-10"
                        />
                        <button
                          type="button"
                          onClick={() => setShowPassword(!showPassword)}
                          className="absolute inset-y-0 right-0 flex items-center pr-3"
                        >
                          {showPassword ? (
                            <EyeSlashIcon className="h-5 w-5 text-gray-400" />
                          ) : (
                            <EyeIcon className="h-5 w-5 text-gray-400" />
                          )}
                        </button>
                      </div>
                    </div>

                    <div className="flex items-center justify-between">
                      <div className="flex items-center">
                        <input
                          id="rememberMe"
                          type="checkbox"
                          {...register('rememberMe')}
                          className="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        />
                        <label htmlFor="rememberMe" className="ml-2 block text-sm text-gray-700">
                          로그인 상태 유지
                        </label>
                      </div>
                    </div>

                    <Button
                      type="submit"
                      disabled={isSubmitting}
                      className="w-full"
                      size="lg"
                    >
                      {isSubmitting ? (
                        <LoadingSpinner size="sm" className="mr-2" />
                      ) : (
                        <ArrowRightIcon className="mr-2 h-5 w-5" />
                      )}
                      로그인
                    </Button>

                    <div className="relative">
                      <div className="absolute inset-0 flex items-center">
                        <div className="w-full border-t border-gray-300" />
                      </div>
                      <div className="relative flex justify-center text-sm">
                        <span className="bg-white px-2 text-gray-500">
                          또는 SSO로 로그인
                        </span>
                      </div>
                    </div>

                    <button
                      type="button"
                      onClick={() =>