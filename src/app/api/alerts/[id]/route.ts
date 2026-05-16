import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await request.json();

    const alert = await db.alert.update({
      where: { id },
      data: {
        ...(body.read !== undefined && { read: body.read }),
      },
    });

    return NextResponse.json(alert);
  } catch (error) {
    console.error('Alert PATCH error:', error);
    return NextResponse.json({ error: 'Failed to update alert' }, { status: 500 });
  }
}
